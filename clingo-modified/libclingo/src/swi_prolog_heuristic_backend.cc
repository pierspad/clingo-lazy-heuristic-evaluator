#include "clingo/swi_prolog_heuristic_backend.hh"

#include <cstdlib>
#include <iostream>
#include <stdexcept>

#ifdef CLINGO_USE_SWIPL
#include <SWI-Prolog.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <unistd.h>
#include <vector>
#endif

struct SWIPrologHeuristicBackend::Impl {
#ifdef CLINGO_USE_SWIPL
    std::string runtime_path;
    size_t query_count = 0;
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

class PrologStringBuffers {
public:
    PrologStringBuffers() {
        PL_mark_string_buffers(&mark_);
    }

    PrologStringBuffers(PrologStringBuffers const &) = delete;
    PrologStringBuffers &operator=(PrologStringBuffers const &) = delete;

    ~PrologStringBuffers() {
        PL_release_string_buffers_from_mark(mark_);
    }

private:
    buf_mark_t mark_;
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
}

void retract_runtime_database() {
    std::vector<std::string> predicates = {
        "true_atom(_)",
        "false_atom(_)",
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
    out << ":- dynamic true_atom/1.\n";
    out << ":- dynamic false_atom/1.\n";
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

Clingo::Symbol parse_symbol_from_term(term_t term) {
    char *chars = nullptr;
    if (!PL_get_chars(term, &chars, CVT_WRITE | REP_UTF8 | BUF_DISCARDABLE)) {
        throw std::runtime_error("SWI-Prolog heuristic backend: cannot print target term.");
    }
    std::string const text(chars);
    return Clingo::parse_term(text.c_str());
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
    // Un solo goal per aggiornamento: PL_chars_to_term/PL_call sono il collo
    // di bottiglia della sincronizzazione, quindi retract e assert vengono
    // combinati in un'unica congiunzione. Lo stato Free e' rappresentato
    // dall'assenza dell'atomo da true_atom/1 e false_atom/1.
    std::string const term = atom_term(atom);
    std::string goal = "retractall(true_atom(" + term + ")), retractall(false_atom(" + term + "))";
    if (state == QueryAtomState::True) {
        goal += ", assertz(true_atom(" + term + "))";
    }
    else if (state == QueryAtomState::False) {
        goal += ", assertz(false_atom(" + term + "))";
    }
    call_prolog(goal);

    if (debug_enabled()) {
        char const *state_name = state == QueryAtomState::True ? "true" :
                                 state == QueryAtomState::False ? "false" : "free";
        std::cerr << "[lazy-prolog] state " << state_name << "_atom(" << term << ")\n";
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
        candidate.target = parse_symbol_from_term(av);
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
