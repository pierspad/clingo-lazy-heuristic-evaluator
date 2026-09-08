#include "clingo/swi_prolog_heuristic_backend.hh"

#include <cstdlib>
#include <iostream>
#include <stdexcept>

#ifdef CLINGO_USE_SWIPL
#include <SWI-Prolog.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <unistd.h>
#include <vector>
#endif

#ifdef CLINGO_USE_SWIPL
namespace {

// ---------------------------------------------------------------------------
//  Trail letto, non rispecchiato
//
//  true_atom/1 e false_atom/1 NON sono piu' fatti dinamici asserted a ogni
//  cambio sul trail: sono predicati foreign che leggono direttamente lo stato
//  mantenuto qui sotto in C++. Il motivo e' misurato: la vecchia
//  sincronizzazione costruiva per OGNI letterale un goal come stringa e lo
//  passava a PL_chars_to_term, cioe' al reader di Prolog (tokenizer, operatori,
//  atom table), due retractall + un assertz per chiamata, per lit e -lit a ogni
//  cambio. Su PUP double-200 erano 17.5s di sincronizzazione contro 1.75s di
//  valutazione vera. Qui set_atom_state diventa un aggiornamento di hash map e
//  quel costo sparisce dal profilo invece di essere reso piu' economico.
//
//  I predicati sono NON DETERMINISTICI perche' servono in due modi diversi:
//  come test di appartenenza a argomento ground (\+ true_atom(c(3))) e come
//  generatore a argomento parziale (aggregate_all(sum(Y), holds(c(Y)), S)),
//  dove devono enumerare tutti gli atomi veri che unificano con c(Y).
// ---------------------------------------------------------------------------

struct SymbolHash {
    size_t operator()(Clingo::Symbol const &s) const { return s.hash(); }
};

using SymbolSet = std::unordered_set<Clingo::Symbol, SymbolHash>;
using Signature = std::pair<std::string, size_t>;

struct SignatureHash {
    size_t operator()(Signature const &s) const {
        return std::hash<std::string>()(s.first) ^ (std::hash<size_t>()(s.second) << 1);
    }
};

// Firma (nome, arieta') di un simbolo clingo, usata come chiave di bucket:
// l'enumerazione parte sempre da un termine la cui firma e' nota, quindi
// scandire un bucket invece dell'intero trail e' cio' che tiene la query
// vicina al costo della sola valutazione.
bool symbol_signature(Clingo::Symbol const &symbol, Signature &out) {
    if (symbol.type() != Clingo::SymbolType::Function) return false;
    out = Signature(symbol.name(), symbol.arguments().size());
    return true;
}

class AtomStore {
public:
    void clear() {
        true_.clear();
        false_.clear();
        sequence_.clear();
        counter_ = 0;
    }

    void set(Clingo::Symbol const &symbol, QueryAtomState state) {
        Signature sig;
        if (!symbol_signature(symbol, sig)) return;
        // Lo stato Free e' l'assenza da entrambi gli insiemi: stessa
        // convenzione della versione a fatti dinamici, cosi' alpha_not/1 e
        // clingo_not/1 non cambiano significato.
        true_[sig].erase(symbol);
        false_[sig].erase(symbol);
        if (state == QueryAtomState::True) {
            true_[sig].insert(symbol);
            sequence_[symbol] = ++counter_;
        }
        else if (state == QueryAtomState::False) {
            false_[sig].insert(symbol);
            sequence_[symbol] = ++counter_;
        }
    }

    bool contains(bool positive, Clingo::Symbol const &symbol) const {
        Signature sig;
        if (!symbol_signature(symbol, sig)) return false;
        auto const &table = positive ? true_ : false_;
        auto it = table.find(sig);
        if (it == table.end()) return false;
        return it->second.find(symbol) != it->second.end();
    }

    // Istantanea dei candidati: enumerare su una copia invece che su iteratori
    // vivi rende l'enumerazione immune a qualunque aggiornamento concorrente
    // dello store, e costa una sola allocazione per chiamata non deterministica.
    void snapshot(bool positive, Signature const &sig, std::vector<Clingo::Symbol> &out) const {
        auto const &table = positive ? true_ : false_;
        auto it = table.find(sig);
        if (it == table.end()) return;
        out.reserve(it->second.size());
        for (auto const &symbol : it->second) {
            out.push_back(symbol);
        }
        sort_by_sequence(out);
    }

    void snapshot_all(bool positive, std::vector<Clingo::Symbol> &out) const {
        auto const &table = positive ? true_ : false_;
        for (auto const &bucket : table) {
            for (auto const &symbol : bucket.second) {
                out.push_back(symbol);
            }
        }
        sort_by_sequence(out);
    }

private:
    // L'enumerazione riproduce l'ordine di assertz della versione a fatti
    // dinamici. Non e' un dettaglio estetico: quando due candidati pareggiano
    // su (priorita', peso) vince quello incontrato per primo, quindi l'ordine
    // e' osservabile nelle traiettorie di ricerca. Scandire direttamente un
    // unordered_set lo legherebbe all'ordine di hash, che non e' garantito
    // stabile fra toolchain diverse: le stesse istanze darebbero conteggi di
    // scelte diversi fra il portatile e i nodi del cluster.
    void sort_by_sequence(std::vector<Clingo::Symbol> &symbols) const {
        std::sort(symbols.begin(), symbols.end(),
                  [this](Clingo::Symbol const &a, Clingo::Symbol const &b) {
                      auto ia = sequence_.find(a);
                      auto ib = sequence_.find(b);
                      uint64_t const sa = ia == sequence_.end() ? 0 : ia->second;
                      uint64_t const sb = ib == sequence_.end() ? 0 : ib->second;
                      return sa < sb;
                  });
    }

    std::unordered_map<Signature, SymbolSet, SignatureHash> true_;
    std::unordered_map<Signature, SymbolSet, SignatureHash> false_;
    std::unordered_map<Clingo::Symbol, uint64_t, SymbolHash> sequence_;
    uint64_t counter_ = 0;
};

// Un solo motore SWI per processo e un solo backend registrato (il propagatore
// e' registrato sequenziale, v. clingo_app.cc), quindi i predicati foreign,
// che non possono ricevere user data da PL_register_foreign, raggiungono lo
// store per questa via.
AtomStore *g_active_store = nullptr;

} // namespace
#endif

struct SWIPrologHeuristicBackend::Impl {
#ifdef CLINGO_USE_SWIPL
    std::string runtime_path;
    size_t query_count = 0;
    AtomStore store;
#endif
};

SWIPrologHeuristicBackend::SWIPrologHeuristicBackend()
    : impl_(std::make_unique<Impl>()) {}

SWIPrologHeuristicBackend::~SWIPrologHeuristicBackend() {
#ifdef CLINGO_USE_SWIPL
    if (!impl_->runtime_path.empty()) {
        std::remove(impl_->runtime_path.c_str());
    }
#endif
}

#ifdef CLINGO_USE_SWIPL
namespace {

class PrologForeignFrame {
public:
    PrologForeignFrame()
        : frame_(PL_open_foreign_frame()) {}

    PrologForeignFrame(PrologForeignFrame const &) = delete;
    PrologForeignFrame &operator=(PrologForeignFrame const &) = delete;

    ~PrologForeignFrame() {
        PL_discard_foreign_frame(frame_);
    }

private:
    fid_t frame_;
};

class PrologQuery {
public:
    PrologQuery(predicate_t predicate, term_t args)
        : query_(PL_open_query(nullptr, PL_Q_NORMAL, predicate, args)) {}

    PrologQuery(PrologQuery const &) = delete;
    PrologQuery &operator=(PrologQuery const &) = delete;

    ~PrologQuery() {
        if (query_ != 0) {
            PL_cut_query(query_);
        }
    }

    int next_solution() {
        return PL_next_solution(query_);
    }

    void close() {
        if (query_ != 0) {
            PL_close_query(query_);
            query_ = 0;
        }
    }

private:
    qid_t query_;
};

// RAII per delimitare la vita dei buffer di stringhe temporanee che SWI-Prolog
// alloca internamente (PL_get_chars/PL_get_atom_chars con BUF_STACK o
// BUF_DISCARDABLE, vedi parse_symbol_from_term/get_bool_atom sopra). Qui non
// siamo dentro un predicato foreign richiamato da Prolog: e' codice host che
// pilota la query con PL_open_query/PL_next_solution in un ciclo chiamato una
// volta per ogni decisione del solver, quindi il rilascio automatico "a fine
// predicato foreign" di SWI-Prolog non ci copre - senza questo marker i buffer
// si accumulerebbero per l'intera durata del solve invece di essere rilasciati
// a ogni soluzione.
//
// PL_mark_string_buffers()/PL_release_string_buffers_from_mark() (e il tipo
// buf_mark_t) non esistono nelle versioni piu' vecchie di SWI-Prolog (es. la
// 7.6.4 di Debian 10/buster, quella dei nodi del cluster). CLINGO_SWIPL_HAS_STRING_BUFFER_MARKS
// e' definita da CMake solo se una compilazione di prova con l'header/lib
// effettivi ha successo (vedi clingo-prolog/CMakeLists.txt) — niente soglie
// su PLVERSION, che sarebbero fragili con le patch di backport delle distro.
// Se l'API non c'e', la classe diventa un guscio RAII vuoto: i buffer restano
// a carico del meccanismo di default di SWI-Prolog invece di essere liberati
// esplicitamente a ogni soluzione. Non e' una perdita di memoria (i buffer
// BUF_STACK vengono comunque riciclati al loro punto naturale), solo un
// bound di memoria residente meno stretto durante query molto lunghe.
class PrologStringBuffers {
public:
    PrologStringBuffers() {
#ifdef CLINGO_SWIPL_HAS_STRING_BUFFER_MARKS
        PL_mark_string_buffers(&mark_);
#endif
    }

    PrologStringBuffers(PrologStringBuffers const &) = delete;
    PrologStringBuffers &operator=(PrologStringBuffers const &) = delete;

    ~PrologStringBuffers() {
#ifdef CLINGO_SWIPL_HAS_STRING_BUFFER_MARKS
        PL_release_string_buffers_from_mark(mark_);
#endif
    }

private:
#ifdef CLINGO_SWIPL_HAS_STRING_BUFFER_MARKS
    buf_mark_t mark_;
#endif
};

bool debug_enabled() {
    // Letto una sola volta: la variabile d'ambiente non cambia a processo avviato
    // e questa funzione e' chiamata su ogni sincronizzazione di stato.
    static bool const enabled = [] {
        char const *value = std::getenv("LAZY_HEURISTIC_DEBUG");
        if (value == nullptr) return false;

        std::string const text(value);
        return text == "1" ||
               text == "true" ||
               text == "TRUE" ||
               text == "on" ||
               text == "ON" ||
               text == "yes" ||
               text == "YES";
    }();
    return enabled;
}

std::string atom_term(Clingo::Symbol const &symbol) {
    return symbol.to_string();
}


// PL_get_name_arity cambia firma fra le versioni di SWI-Prolog: il terzo
// parametro e' "int *arity" fino alla 8.x (e' quello che hanno i nodi del
// cluster, /usr/lib/swi-prolog/include) e "size_t *arity" dalla 9 in poi.
// Il tipo viene dedotto dalla firma reale della funzione, cosi' il file
// compila su entrambe senza condizionali su PLVERSION, che sarebbero fragili
// con le patch di backport delle distro (stesso criterio adottato per
// CLINGO_SWIPL_HAS_STRING_BUFFER_MARKS).
// PL_ARITY_AS_SIZE e' definita dall'header stesso quando l'arieta' e' size_t;
// e' il flag che SWI-Prolog espone proprio per questo, quindi non serve
// guardare la versione. Cambia anche il tipo di ritorno (int sulle vecchie,
// bool sulle nuove): qui viene solo testato, quindi la conversione implicita
// va bene in entrambi i casi.
#ifdef PL_ARITY_AS_SIZE
using PrologArity = size_t;
#else
using PrologArity = int;
#endif

bool get_name_arity(term_t term, atom_t *name, size_t &arity) {
    PrologArity native = 0;
    if (!PL_get_name_arity(term, name, &native)) return false;
    arity = static_cast<size_t>(native);
    return true;
}

bool put_symbol(term_t out, Clingo::Symbol const &symbol);

bool put_symbol_arguments(term_t out, Clingo::Symbol const &symbol) {
    auto const args = symbol.arguments();
    if (args.empty()) {
        return PL_put_atom_chars(out, symbol.name()) != 0;
    }
    term_t argv = PL_new_term_refs(static_cast<int>(args.size()));
    for (size_t i = 0; i < args.size(); ++i) {
        if (!put_symbol(argv + i, args[i])) return false;
    }
    functor_t functor = PL_new_functor(PL_new_atom(symbol.name()), static_cast<int>(args.size()));
    return PL_cons_functor_v(out, functor, argv) != 0;
}

// Simbolo clingo -> termine Prolog, costruito con l'API dei termini invece che
// stampato e riletto. E' la meta' "in ingresso" della rimozione dei parser.
bool put_symbol(term_t out, Clingo::Symbol const &symbol) {
    switch (symbol.type()) {
        case Clingo::SymbolType::Number:
            return PL_put_integer(out, symbol.number()) != 0;
        case Clingo::SymbolType::String:
            return PL_put_string_chars(out, symbol.string()) != 0;
        case Clingo::SymbolType::Infimum:
            return PL_put_atom_chars(out, "#inf") != 0;
        case Clingo::SymbolType::Supremum:
            return PL_put_atom_chars(out, "#sup") != 0;
        case Clingo::SymbolType::Function: {
            if (symbol.is_positive()) {
                return put_symbol_arguments(out, symbol);
            }
            // Simbolo con segno negativo (-p(X)): il termine corrispondente e'
            // -(p(X)), coerente con come symbol.to_string() lo stampava prima.
            term_t inner = PL_new_term_refs(1);
            if (!put_symbol_arguments(inner, symbol)) return false;
            functor_t functor = PL_new_functor(PL_new_atom("-"), 1);
            return PL_cons_functor_v(out, functor, inner) != 0;
        }
    }
    return false;
}

// Termine Prolog -> simbolo clingo, senza passare da PL_get_chars +
// Clingo::parse_term. E' la meta' "in uscita": quel round-trip testuale stava
// sul percorso dei risultati della query, cioe' sul secondo dei due numeri
// (1.75s di valutazione a double-200), ed era il secondo parser nascosto.
bool symbol_from_term(term_t term, Clingo::Symbol &out) {
    switch (PL_term_type(term)) {
        case PL_INTEGER: {
            int64_t value = 0;
            if (!PL_get_int64(term, &value)) return false;
            out = Clingo::Number(static_cast<int>(value));
            return true;
        }
        case PL_ATOM: {
            char *text = nullptr;
            if (!PL_get_atom_chars(term, &text)) return false;
            if (std::strcmp(text, "#inf") == 0) { out = Clingo::Infimum(); return true; }
            if (std::strcmp(text, "#sup") == 0) { out = Clingo::Supremum(); return true; }
            out = Clingo::Function(text, {});
            return true;
        }
        case PL_STRING: {
            char *text = nullptr;
            size_t length = 0;
            if (!PL_get_string_chars(term, &text, &length)) return false;
            out = Clingo::String(text);
            return true;
        }
        case PL_TERM: {
            atom_t name;
            size_t arity = 0;
            if (!get_name_arity(term, &name, arity)) return false;
            std::string const text(PL_atom_chars(name));

            std::vector<Clingo::Symbol> arguments;
            arguments.reserve(arity);
            term_t argument = PL_new_term_ref();
            for (size_t i = 1; i <= arity; ++i) {
                if (!PL_get_arg(static_cast<int>(i), term, argument)) return false;
                Clingo::Symbol child;
                if (!symbol_from_term(argument, child)) return false;
                arguments.push_back(child);
            }

            // -(p(X)) e' il simbolo negativo p(X), speculare a put_symbol.
            if (text == "-" && arity == 1 &&
                arguments[0].type() == Clingo::SymbolType::Function) {
                out = Clingo::Function(arguments[0].name(), arguments[0].arguments(), false);
                return true;
            }
            out = Clingo::Function(text.c_str(), arguments);
            return true;
        }
        default:
            return false;
    }
}

// Contesto di un'enumerazione non deterministica in corso. Vive fra una
// soluzione e la successiva, ed e' distrutto sia all'esaurimento sia sul taglio
// (PL_PRUNED): senza quel ramo, ogni once/1 o \+ su un generatore lascerebbe
// il contesto in giro per l'intera durata del solve.
struct EnumerationContext {
    std::vector<Clingo::Symbol> candidates;
    size_t index = 0;
};

foreign_t enumerate_next(term_t argument, EnumerationContext *context) {
    while (context->index < context->candidates.size()) {
        Clingo::Symbol const symbol = context->candidates[context->index++];

        // Ogni tentativo dentro il proprio frame: un'unificazione fallita non
        // deve lasciare ne' term refs ne' binding parziali al tentativo dopo.
        fid_t frame = PL_open_foreign_frame();
        term_t candidate = PL_new_term_ref();
        if (put_symbol(candidate, symbol) && PL_unify(argument, candidate)) {
            PL_close_foreign_frame(frame); // tiene i binding dell'unificazione
            if (context->index >= context->candidates.size()) {
                delete context; // ultima soluzione: successo deterministico
                return TRUE;
            }
            PL_retry_address(context);
        }
        PL_rewind_foreign_frame(frame);
        PL_close_foreign_frame(frame);
    }
    delete context;
    return FALSE;
}

foreign_t atom_state_predicate(term_t argument, control_t handle, bool positive) {
    switch (PL_foreign_control(handle)) {
        case PL_FIRST_CALL: {
            if (g_active_store == nullptr) return FALSE;

            // Argomento ground: test di appartenenza, deterministico. E' il
            // caso caldo (\+ true_atom(...) dentro alpha_not/target_available)
            // e non alloca niente.
            if (PL_is_ground(argument)) {
                Clingo::Symbol symbol;
                if (!symbol_from_term(argument, symbol)) return FALSE;
                return g_active_store->contains(positive, symbol) ? TRUE : FALSE;
            }

            auto *context = new EnumerationContext();
            atom_t name;
            size_t arity = 0;
            if (get_name_arity(argument, &name, arity)) {
                char const *text = PL_atom_chars(name);
                g_active_store->snapshot(positive, Signature(text, arity), context->candidates);
            }
            else {
                // Variabile nuda: nessuna firma da cui partire, si enumera
                // tutto. Gli encoding della suite non lo fanno, ma un corpo
                // Prolog arbitrario puo'.
                g_active_store->snapshot_all(positive, context->candidates);
            }
            return enumerate_next(argument, context);
        }
        case PL_REDO: {
            auto *context = static_cast<EnumerationContext *>(PL_foreign_context_address(handle));
            return enumerate_next(argument, context);
        }
        case PL_PRUNED: {
            delete static_cast<EnumerationContext *>(PL_foreign_context_address(handle));
            return TRUE;
        }
        default:
            return FALSE;
    }
}

foreign_t pl_true_atom(term_t argument, control_t handle) {
    return atom_state_predicate(argument, handle, true);
}

foreign_t pl_false_atom(term_t argument, control_t handle) {
    return atom_state_predicate(argument, handle, false);
}

void register_foreign_predicates() {
    static bool registered = false;
    if (registered) return;
    PL_register_foreign("true_atom", 1, reinterpret_cast<pl_function_t>(pl_true_atom), PL_FA_NONDETERMINISTIC);
    PL_register_foreign("false_atom", 1, reinterpret_cast<pl_function_t>(pl_false_atom), PL_FA_NONDETERMINISTIC);
    registered = true;
}

std::string ensure_period(std::string rule) {
    while (!rule.empty() && std::isspace(static_cast<unsigned char>(rule.back()))) {
        rule.pop_back();
    }
    if (rule.empty() || rule.back() != '.') {
        rule.push_back('.');
    }
    return rule;
}

void call_prolog(std::string const &goal) {
    PrologForeignFrame frame;
    term_t term = PL_new_term_ref();
    if (!PL_chars_to_term(goal.c_str(), term)) {
        throw std::runtime_error("SWI-Prolog heuristic backend: cannot parse goal: " + goal);
    }
    if (!PL_call(term, nullptr)) {
        throw std::runtime_error("SWI-Prolog heuristic backend: goal failed: " + goal);
    }
}

void ensure_engine() {
    int argc = 0;
    char **argv = nullptr;
    if (PL_is_initialised(&argc, &argv)) return;

    char arg0[] = "clingo-lazy-heuristics";
    char arg1[] = "-q";
    char arg2[] = "--nosignals";
    char *plav[] = {arg0, arg1, arg2, nullptr};
    if (!PL_initialise(3, plav)) {
        throw std::runtime_error("SWI-Prolog heuristic backend: PL_initialise failed.");
    }
    call_prolog("set_prolog_flag(verbose, silent)");
    call_prolog("set_prolog_flag(unknown, fail)");
    call_prolog("set_prolog_flag(verbose, normal)");
    call_prolog("set_prolog_flag(debug_on_error, false)");
    // Dopo PL_initialise e prima di qualunque consult: il programma runtime
    // fa riferimento a true_atom/1 e false_atom/1, che devono gia' esistere
    // come foreign quando viene caricato.
    register_foreign_predicates();
}

void retract_runtime_database() {
    std::vector<std::string> predicates = {
        "static_atom(_)",
        "target_atom(_)",
        "n_value(_)",
        "n(_)",
        "holds(_)",
        "holds_pos(_)",
        "clingo_not(_)",
        "alpha_not(_)",
        "target_available(_)",
        "dyn_sum(_, _, _)",
        "dyn_count(_, _)",
        "dyn_min(_, _, _)",
        "dyn_max(_, _, _)",
        "heuristic(_,_,_,_)"
    };
    for (auto const &predicate : predicates) {
        call_prolog("retractall(" + predicate + ")");
    }
}

std::string runtime_program(std::vector<QueryHeuristicRule> const &rules,
                            std::vector<Clingo::Symbol> const &static_atoms,
                            std::vector<Clingo::Symbol> const &known_atoms,
                            bool has_n,
                            int n_value) {
    std::ostringstream out;
    // true_atom/1 e false_atom/1 NON sono dichiarati dinamici: sono predicati
    // foreign registrati da register_foreign_predicates(). Dichiararli qui
    // creerebbe un predicato dinamico vuoto che oscurerebbe quello foreign.
    out << ":- dynamic static_atom/1.\n";
    out << ":- dynamic target_atom/1.\n";
    out << ":- dynamic n_value/1.\n";
    out << ":- dynamic n/1.\n";
    out << ":- dynamic holds/1.\n";
    out << ":- dynamic holds_pos/1.\n";
    out << ":- dynamic clingo_not/1.\n";
    out << ":- dynamic alpha_not/1.\n";
    out << ":- dynamic target_available/1.\n";
    out << ":- dynamic dyn_sum/3.\n";
    out << ":- dynamic dyn_count/2.\n";
    out << ":- dynamic dyn_min/3.\n";
    out << ":- dynamic dyn_max/3.\n";
    out << ":- dynamic heuristic/4.\n";
    out << ":- use_module(library(aggregate)).\n";
    out << "holds(A) :- true_atom(A).\n";
    out << "holds(A) :- static_atom(A), \\+ true_atom(A).\n";
    out << "holds_pos(A) :- holds(A).\n";
    out << "clingo_not(A) :- false_atom(A).\n";
    out << "alpha_not(A)  :- \\+ holds(A).\n";
    out << "n(N) :- n_value(N).\n";
    out << "target_available(A) :- target_atom(A), \\+ true_atom(A), \\+ false_atom(A).\n";
    out << "dyn_sum(Goal, Template, Sum) :- aggregate_all(sum(Template), Goal, Sum).\n";
    out << "dyn_count(Goal, Count) :- aggregate_all(count, Goal, Count).\n";
    out << "dyn_min(Goal, Template, Min) :- (aggregate_all(min(Template), Goal, R) -> Min = R ; Min = 0).\n";
    out << "dyn_max(Goal, Template, Max) :- (aggregate_all(max(Template), Goal, R) -> Max = R ; Max = 0).\n";

    for (auto const &symbol : static_atoms) {
        out << "static_atom(" << atom_term(symbol) << ").\n";
    }
    for (auto const &symbol : known_atoms) {
        out << "target_atom(" << atom_term(symbol) << ").\n";
    }
    if (has_n) {
        out << "n_value(" << n_value << ").\n";
    }
    for (auto const &rule : rules) {
        out << ensure_period(rule.prolog_rule) << "\n";
    }
    return out.str();
}

std::string write_runtime_file(std::string const &program) {
    static size_t counter = 0;
    std::ostringstream path;
    path << "/tmp/clingo_lazy_prolog_" << getpid() << "_" << counter++ << ".pl";
    std::ofstream out(path.str().c_str());
    if (!out) {
        throw std::runtime_error("SWI-Prolog heuristic backend: cannot write runtime file.");
    }
    out << program;
    out.close();
    return path.str();
}

bool get_bool_atom(term_t term, bool &value) {
    char *name = nullptr;
    if (!PL_get_atom_chars(term, &name)) return false;
    std::string text(name);
    if (text == "true") {
        value = true;
        return true;
    }
    if (text == "false") {
        value = false;
        return true;
    }
    return false;
}

} // namespace
#endif

void SWIPrologHeuristicBackend::initialize(std::vector<QueryHeuristicRule> const &rules,
                                           std::vector<Clingo::Symbol> const &static_atoms,
                                           std::vector<Clingo::Symbol> const &known_atoms,
                                           bool has_n,
                                           int n_value) {
#ifndef CLINGO_USE_SWIPL
    static_cast<void>(rules);
    static_cast<void>(static_atoms);
    static_cast<void>(known_atoms);
    static_cast<void>(has_n);
    static_cast<void>(n_value);
    std::cerr << "[lazy-prolog] SWI-Prolog backend requested, but this clingo build was compiled without "
                 "CLINGO_USE_SWIPL=ON.\n";
    throw std::runtime_error("SWI-Prolog heuristic backend requested, but clingo was built without CLINGO_USE_SWIPL.");
#else
    ensure_engine();
    impl_->store.clear();
    g_active_store = &impl_->store;
    retract_runtime_database();
    if (!impl_->runtime_path.empty()) {
        std::remove(impl_->runtime_path.c_str());
        impl_->runtime_path.clear();
    }

    auto program = runtime_program(rules, static_atoms, known_atoms, has_n, n_value);
    impl_->runtime_path = write_runtime_file(program);
    call_prolog("consult('" + impl_->runtime_path + "')");

    if (debug_enabled()) {
        std::cerr << "[lazy-prolog] initialized with " << rules.size()
                  << " rule(s), " << static_atoms.size() << " static atom(s), "
                  << known_atoms.size() << " known atom(s)\n";
        std::cerr << "[lazy-prolog] runtime file " << impl_->runtime_path << "\n";
    }
#endif
}

void SWIPrologHeuristicBackend::set_atom_state(Clingo::Symbol const &atom, QueryAtomState state) {
#ifndef CLINGO_USE_SWIPL
    static_cast<void>(atom);
    static_cast<void>(state);
    throw std::runtime_error("SWI-Prolog heuristic backend requested, but clingo was built without CLINGO_USE_SWIPL.");
#else
    // Nessuna chiamata a Prolog: lo stato del trail vive qui, e true_atom/1 e
    // false_atom/1 lo leggono quando la query li interroga. La versione
    // precedente costruiva qui un goal testuale e lo faceva leggere a
    // PL_chars_to_term a ogni letterale; era il termine "sync" della formula di
    // overhead, e questa riga e' cio' che lo azzera.
    impl_->store.set(atom, state);

    if (debug_enabled()) {
        char const *state_name = state == QueryAtomState::True ? "true" :
                                 state == QueryAtomState::False ? "false" : "free";
        std::cerr << "[lazy-prolog] state " << state_name << "_atom(" << atom_term(atom) << ")\n";
    }
#endif
}

std::vector<QueryHeuristicCandidate> SWIPrologHeuristicBackend::query_applicable_candidates() {
#ifndef CLINGO_USE_SWIPL
    throw std::runtime_error("SWI-Prolog heuristic backend requested, but clingo was built without CLINGO_USE_SWIPL.");
#else
    ++impl_->query_count;
    std::vector<QueryHeuristicCandidate> result;

    predicate_t predicate = PL_predicate("heuristic", 4, nullptr);
    PrologForeignFrame frame;
    term_t av = PL_new_term_refs(4);
    PrologQuery query(predicate, av);
    size_t rule_index = 0;
    while (query.next_solution()) {
        PrologForeignFrame solution_frame;
        PrologStringBuffers string_buffers;

        int weight = 0;
        int priority = 0;
        if (!PL_get_integer(av + 1, &weight) ||
            !PL_get_integer(av + 2, &priority)) {
            throw std::runtime_error("SWI-Prolog heuristic backend: heuristic weight and priority must be integers.");
        }

        bool sign = true;
        if (!get_bool_atom(av + 3, sign)) {
            throw std::runtime_error("SWI-Prolog heuristic backend: heuristic modifier must be true or false.");
        }

        QueryHeuristicCandidate candidate;
        Clingo::Symbol target;
        if (!symbol_from_term(av, target)) {
            throw std::runtime_error("SWI-Prolog heuristic backend: cannot convert target term.");
        }
        candidate.target = target;
        candidate.weight = weight;
        candidate.priority = priority;
        candidate.sign = sign;
        candidate.semantics = HeuristicSemantics::Alpha;
        candidate.rule_index = rule_index++;
        result.push_back(std::move(candidate));
    }
    query.close();

    if (debug_enabled()) {
        std::cerr << "[lazy-prolog] decide call " << impl_->query_count
                  << " produced " << result.size() << " candidate(s)\n";
    }

    return result;
#endif
}
