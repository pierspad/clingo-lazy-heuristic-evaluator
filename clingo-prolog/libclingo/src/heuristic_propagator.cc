#include "clingo/heuristic_propagator.hh"
#include "clingo/heuristic_symbol.hh"
#include "clingo/swi_prolog_heuristic_backend.hh"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <unordered_set>
#include <utility>

namespace {
using LazyStatsClock = std::chrono::steady_clock;

double elapsed_ms(LazyStatsClock::time_point start) {
    return std::chrono::duration<double, std::milli>(LazyStatsClock::now() - start).count();
}

class ScopedLazyStatsTimer {
public:
    ScopedLazyStatsTimer(bool active, double &target)
        : active_(active)
        , target_(target)
        , start_(active ? LazyStatsClock::now() : LazyStatsClock::time_point{}) {}

    ScopedLazyStatsTimer(ScopedLazyStatsTimer const &) = delete;
    ScopedLazyStatsTimer &operator=(ScopedLazyStatsTimer const &) = delete;

    ~ScopedLazyStatsTimer() {
        if (active_) {
            target_ += elapsed_ms(start_);
        }
    }

private:
    bool active_;
    double &target_;
    LazyStatsClock::time_point start_;
};
} // namespace



static std::string trim_copy(std::string const &value) {
    auto begin = value.begin();
    while (begin != value.end() && std::isspace(static_cast<unsigned char>(*begin))) {
        ++begin;
    }

    auto end = value.end();
    while (end != begin && std::isspace(static_cast<unsigned char>(*(end - 1)))) {
        --end;
    }

    return std::string(begin, end);
}

static bool is_identifier_start(char ch) {
    return std::isalpha(static_cast<unsigned char>(ch)) || ch == '_';
}

static bool is_identifier_char(char ch) {
    return std::isalnum(static_cast<unsigned char>(ch)) || ch == '_';
}

static size_t find_matching_paren(std::string const &text, size_t open_pos) {
    int depth = 0;
    for (size_t i = open_pos; i < text.size(); ++i) {
        if (text[i] == '(') {
            ++depth;
        }
        else if (text[i] == ')') {
            --depth;
            if (depth == 0) return i;
        }
    }
    return std::string::npos;
}

static std::vector<std::string> split_top_level_args(std::string const &text) {
    std::vector<std::string> args;
    int paren_depth = 0;
    int bracket_depth = 0;
    size_t start = 0;
    for (size_t i = 0; i < text.size(); ++i) {
        char const ch = text[i];
        if (ch == '(') {
            ++paren_depth;
        }
        else if (ch == ')') {
            --paren_depth;
        }
        else if (ch == '[' || ch == '{') {
            ++bracket_depth;
        }
        else if (ch == ']' || ch == '}') {
            --bracket_depth;
        }
        else if (ch == ',' && paren_depth == 0 && bracket_depth == 0) {
            args.push_back(trim_copy(text.substr(start, i - start)));
            start = i + 1;
        }
    }
    args.push_back(trim_copy(text.substr(start)));
    return args;
}

static std::string predicate_signature(std::string const &name, size_t arity) {
    std::ostringstream out;
    out << name << "/" << arity;
    return out.str();
}

static std::string symbol_signature(Clingo::Symbol const &symbol) {
    return predicate_signature(symbol.name(), symbol.arguments().size());
}

static bool extract_term_signature(std::string const &term, std::string &signature) {
    std::string const trimmed = trim_copy(term);
    if (trimmed.empty() || !is_identifier_start(trimmed.front())) return false;

    size_t name_end = 1;
    while (name_end < trimmed.size() && is_identifier_char(trimmed[name_end])) {
        ++name_end;
    }

    std::string const name = trimmed.substr(0, name_end);
    size_t pos = name_end;
    while (pos < trimmed.size() && std::isspace(static_cast<unsigned char>(trimmed[pos]))) {
        ++pos;
    }

    if (pos >= trimmed.size() || trimmed[pos] != '(') {
        signature = predicate_signature(name, 0);
        return true;
    }

    size_t const close_pos = find_matching_paren(trimmed, pos);
    if (close_pos == std::string::npos) return false;

    auto const args = split_top_level_args(trimmed.substr(pos + 1, close_pos - pos - 1));
    signature = predicate_signature(name, args.size());
    return true;
}

static void collect_term_signature(std::unordered_set<std::string> &signatures,
                                   std::string const &term) {
    std::string signature;
    if (extract_term_signature(term, signature)) {
        signatures.insert(std::move(signature));
    }
}

static void collect_wrapper_argument_signatures(std::unordered_set<std::string> &signatures,
                                                std::string const &rule,
                                                std::string const &wrapper_name,
                                                size_t term_arg_index) {
    size_t pos = 0;
    std::string const prefix = wrapper_name + "(";
    while ((pos = rule.find(prefix, pos)) != std::string::npos) {
        if (pos > 0 && is_identifier_char(rule[pos - 1])) {
            pos += prefix.size();
            continue;
        }

        size_t const open_pos = pos + wrapper_name.size();
        size_t const close_pos = find_matching_paren(rule, open_pos);
        if (close_pos == std::string::npos) break;

        auto const args = split_top_level_args(rule.substr(open_pos + 1, close_pos - open_pos - 1));
        if (term_arg_index < args.size()) {
            collect_term_signature(signatures, args[term_arg_index]);
        }
        pos = close_pos + 1;
    }
}

static void replace_all(std::string &text, std::string const &from, std::string const &to) {
    if (from.empty()) return;

    size_t pos = 0;
    while ((pos = text.find(from, pos)) != std::string::npos) {
        bool const left_boundary = pos == 0 || !is_identifier_char(text[pos - 1]);
        bool const right_boundary = from.back() == '(' ||
            pos + from.size() >= text.size() ||
            !is_identifier_char(text[pos + from.size()]);
        if (left_boundary && right_boundary) {
            text.replace(pos, from.size(), to);
            pos += to.size();
        }
        else {
            pos += from.size();
        }
    }
}

static std::string normalize_clingo_like_heuristic_rule(std::string const &raw) {
    std::string normalized = trim_copy(raw);
    std::string const head_prefix = "heuristic(";
    if (normalized.compare(0, head_prefix.size(), head_prefix) != 0) {
        throw std::runtime_error("Lazy heuristic clingo-like: the rule string must start with heuristic(...).");
    }

    normalized.insert(0, "active_");
    normalized = trim_copy(normalized);
    if (normalized.empty() || normalized.back() != '.') {
        normalized.push_back('.');
    }
    return normalized;
}

static size_t find_matching_head_paren(std::string const &rule, size_t open_pos) {
    int depth = 0;
    for (size_t i = open_pos; i < rule.size(); ++i) {
        if (rule[i] == '(') {
            ++depth;
        }
        else if (rule[i] == ')') {
            --depth;
            if (depth == 0) return i;
        }
    }
    return std::string::npos;
}

static std::string normalize_prolog_heuristic_rule(std::string const &raw) {
    std::string normalized = trim_copy(raw);

    std::string const head_prefix = "heuristic(";
    if (normalized.compare(0, head_prefix.size(), head_prefix) != 0) {
        throw std::runtime_error("Lazy heuristic Prolog backend: the rule string must start with heuristic(...).");
    }

    size_t const close_pos = find_matching_head_paren(normalized, head_prefix.size() - 1);
    if (close_pos == std::string::npos) {
        throw std::runtime_error("Lazy heuristic Prolog backend: malformed heuristic(...) rule head.");
    }

    if (normalized.empty() || normalized.back() != '.') {
        normalized.push_back('.');
    }
    return normalized;
}

// Costruisce una QueryHeuristicRule da una stringa heuristic("...").
// La semantica e' dedotta dalla presenza di clingo_not(...) nel corpo:
// in sua assenza vale la semantica Alpha (alpha_not o nessuna negazione).
static QueryHeuristicRule make_query_heuristic_rule(std::string original_rule) {
    QueryHeuristicRule rule;
    rule.original_rule = std::move(original_rule);
    rule.semantics = rule.original_rule.find("clingo_not(") != std::string::npos
        ? HeuristicSemantics::Clingo
        : HeuristicSemantics::Alpha;
    rule.normalized_rule = normalize_clingo_like_heuristic_rule(rule.original_rule);
    rule.prolog_rule = normalize_prolog_heuristic_rule(rule.original_rule);
    return rule;
}

static bool is_clingo_like_static_predicate(Clingo::Symbol const &symbol) {
    if (!is_clingo_symbol_function(symbol) || !symbol.is_positive()) return false;

    std::string const name = symbol.name();
    size_t const arity = symbol.arguments().size();
    return (name == "x" && arity == 1) ||
           (name == "item" && arity == 1) ||
           (name == "dom" && arity == 1) ||
           (name == "range" && arity == 1) ||
           (name == "val" && arity == 1);
}

static std::unordered_set<std::string> collect_query_relevant_predicate_signatures(
    std::vector<QueryHeuristicRule> const &rules
) {
    std::unordered_set<std::string> signatures;

    for (auto const &rule : rules) {
        std::string const normalized = trim_copy(rule.original_rule);
        if (normalized.compare(0, std::string("heuristic(").size(), "heuristic(") == 0) {
            size_t const close_pos = find_matching_paren(normalized, std::string("heuristic").size());
            if (close_pos != std::string::npos) {
                auto const args = split_top_level_args(
                    normalized.substr(std::string("heuristic(").size(),
                                      close_pos - std::string("heuristic(").size())
                );
                if (!args.empty()) {
                    collect_term_signature(signatures, args[0]);
                }
            }
        }

        collect_wrapper_argument_signatures(signatures, normalized, "holds", 0);
        collect_wrapper_argument_signatures(signatures, normalized, "holds_pos", 0);
        collect_wrapper_argument_signatures(signatures, normalized, "clingo_not", 0);
        collect_wrapper_argument_signatures(signatures, normalized, "alpha_not", 0);
        collect_wrapper_argument_signatures(signatures, normalized, "target_available", 0);
    }

    return signatures;
}

static bool is_internal_clingo_like_symbol(Clingo::Symbol const &symbol) {
    if (!is_clingo_symbol_function(symbol)) return true;

    std::string const name = symbol.name();
    return name.empty() ||
           name.rfind("__", 0) == 0 ||
           name == "heuristic" ||
           name == "prolog_heuristic" ||
           name == "active_heuristic";
}

static std::string symbol_to_fact(Clingo::Symbol const &symbol) {
    return symbol.to_string() + ".\n";
}

static std::string false_symbol_to_fact(Clingo::Symbol const &symbol) {
    if (!is_clingo_symbol_function(symbol) || !symbol.is_positive()) return "";

    std::ostringstream out;
    out << "not_" << symbol.name();
    auto const args = symbol.arguments();
    if (!args.empty()) {
        out << "(";
        for (size_t i = 0; i < args.size(); ++i) {
            if (i > 0) out << ",";
            out << args[i];
        }
        out << ")";
    }
    out << ".\n";
    return out.str();
}

static bool parse_clingo_like_sign(Clingo::Symbol const &symbol, bool &sign) {
    if (is_clingo_symbol_function(symbol) && symbol.arguments().empty()) {
        std::string const name = symbol.name();
        if (name == "true") {
            sign = true;
            return true;
        }
        if (name == "false") {
            sign = false;
            return true;
        }
    }
    return false;
}

static char const *heuristic_semantics_name(HeuristicSemantics semantics) {
    return semantics == HeuristicSemantics::Alpha ? "alpha" : "clingo";
}

// I flag d'ambiente sono letti una sola volta: non cambiano a processo
// avviato e queste funzioni sono chiamate nei percorsi caldi
// (propagate/undo/decide).
static bool env_flag_enabled(char const *name) {
    char const *value = std::getenv(name);
    if (value == nullptr) return false;

    std::string const text(value);
    return text == "1" ||
           text == "true" ||
           text == "TRUE" ||
           text == "on" ||
           text == "ON" ||
           text == "yes" ||
           text == "YES";
}

static bool lazy_heuristic_debug_enabled() {
    static bool const enabled = env_flag_enabled("LAZY_HEURISTIC_DEBUG");
    return enabled;
}

static bool lazy_prolog_stats_enabled() {
    static bool const enabled = env_flag_enabled("LAZY_PROLOG_STATS");
    return enabled;
}

static bool lazy_heuristic_use_prolog_backend() {
    static bool const enabled = [] {
        char const *value = std::getenv("LAZY_HEURISTIC_BACKEND");
        return value != nullptr && std::string(value) == "prolog";
    }();
    return enabled;
}

static bool lazy_prolog_alpha_query_ranking() {
    static bool const enabled = [] {
        char const *value = std::getenv("LAZY_PROLOG_RANKING");
        return value == nullptr || std::string(value) != "clingo-like";
    }();
    return enabled;
}

static HeuristicSemantics parse_clingo_like_semantics(Clingo::Symbol const &symbol) {
    if (!is_clingo_symbol_function(symbol) || !symbol.arguments().empty()) {
        throw std::runtime_error("Lazy heuristic clingo-like: the first argument must be the nullary symbol alpha or clingo.");
    }

    std::string const name = symbol.name();
    if (name == "alpha") return HeuristicSemantics::Alpha;
    if (name == "clingo") return HeuristicSemantics::Clingo;

    throw std::runtime_error("Lazy heuristic clingo-like: unsupported semantics '" + name + "'; expected alpha or clingo.");
}


















void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    registered_watch_lits_.clear();
    clingo_like_heuristic_rules_.clear();
    clingo_like_static_facts_.clear();
    clingo_like_static_symbols_.clear();
    solver_lit_by_symbol_.clear();
    symbols_by_watched_solver_lit_.clear();
    symbols_by_solver_lit_.clear();
    query_backend_.reset();
    query_backend_stats_ = QueryBackendStats{};
    use_prolog_query_backend_ = false;
    clingo_like_has_n_ = false;
    clingo_like_n_ = 0;

    auto const atoms = init.symbolic_atoms();
    init_clingo_like_mode(init, atoms);
}

void HeuristicPropagator::init_clingo_like_mode(Clingo::PropagateInit &init,
                                                Clingo::SymbolicAtoms const &atoms) {
    std::unordered_set<std::string> static_fact_set;
    std::unordered_set<Clingo::Symbol> static_symbol_set;
    bool const debug = lazy_heuristic_debug_enabled();
    bool const stats = lazy_prolog_stats_enabled();
    bool saw_legacy_prolog_heuristic = false;

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const symbol = it->symbol();

        bool const is_heuristic = symbol.match("heuristic", 1);
        bool const is_legacy_heuristic = !is_heuristic && symbol.match("prolog_heuristic", 1);
        if (is_heuristic || is_legacy_heuristic) {
            auto const args = symbol.arguments();
            if (args.size() != 1 || args[0].type() != Clingo::SymbolType::String) {
                throw std::runtime_error(std::string("Lazy heuristic Prolog backend: ") +
                                         (is_heuristic ? "heuristic/1" : "prolog_heuristic/1") +
                                         " expects a string rule.");
            }
            clingo_like_heuristic_rules_.push_back(make_query_heuristic_rule(args[0].string()));
            saw_legacy_prolog_heuristic = saw_legacy_prolog_heuristic || is_legacy_heuristic;
        }
    }

    use_prolog_query_backend_ = !clingo_like_heuristic_rules_.empty() && lazy_heuristic_use_prolog_backend();
    auto const relevant_predicates = collect_query_relevant_predicate_signatures(clingo_like_heuristic_rules_);
    size_t considered_atoms = 0;
    size_t ignored_irrelevant_atoms = 0;
    std::unordered_set<std::string> ignored_signatures;

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const symbol = it->symbol();
        if (!is_clingo_symbol_function(symbol) || is_internal_clingo_like_symbol(symbol)) continue;
        ++considered_atoms;

        if (use_prolog_query_backend_) {
            std::string const signature = symbol_signature(symbol);
            if (relevant_predicates.find(signature) == relevant_predicates.end()) {
                ++ignored_irrelevant_atoms;
                ignored_signatures.insert(signature);
                if (symbol.match("x", 1)) {
                    auto const args = symbol.arguments();
                    if (args.size() == 1 && args[0].type() == Clingo::SymbolType::Number) {
                        clingo_like_n_ = std::max(clingo_like_n_, args[0].number());
                        clingo_like_has_n_ = true;
                    }
                }
                continue;
            }
        }

        if (is_clingo_like_static_predicate(symbol)) {
            static_fact_set.insert(symbol_to_fact(symbol));
            static_symbol_set.insert(symbol);

            if (symbol.match("x", 1)) {
                auto const args = symbol.arguments();
                if (args.size() == 1 && args[0].type() == Clingo::SymbolType::Number) {
                    clingo_like_n_ = std::max(clingo_like_n_, args[0].number());
                    clingo_like_has_n_ = true;
                }
            }
            continue;
        }

        Clingo::literal_t const solver_lit = init.solver_literal(it->literal());
        if (solver_lit != 0 && solver_lit_by_symbol_.emplace(symbol, solver_lit).second) {
            symbols_by_watched_solver_lit_[solver_lit].push_back(symbol);
            symbols_by_solver_lit_.emplace_back(solver_lit, symbol);
        }
    }

    clingo_like_static_facts_.assign(static_fact_set.begin(), static_fact_set.end());
    std::sort(clingo_like_static_facts_.begin(), clingo_like_static_facts_.end());
    clingo_like_static_symbols_.assign(static_symbol_set.begin(), static_symbol_set.end());
    std::sort(clingo_like_static_symbols_.begin(), clingo_like_static_symbols_.end(), [](Clingo::Symbol const &a,
                                                                                         Clingo::Symbol const &b) {
        return a.to_string() < b.to_string();
    });
    if (debug && !clingo_like_heuristic_rules_.empty()) {
        std::cerr << "[lazy-heuristic] collected " << clingo_like_heuristic_rules_.size()
                  << " query string rule(s)\n";
        for (size_t i = 0; i < clingo_like_heuristic_rules_.size(); ++i) {
            auto const &rule = clingo_like_heuristic_rules_[i];
            std::cerr << "  [" << i << "] semantics=" << heuristic_semantics_name(rule.semantics)
                      << " original=" << rule.original_rule
                      << " normalized=" << rule.prolog_rule
                      << "\n";
        }
        if (saw_legacy_prolog_heuristic) {
            std::cerr << "[lazy-heuristic] prolog_heuristic/... accepted as legacy alias\n";
        }
        if (clingo_like_has_n_) {
            std::cerr << "[lazy-heuristic] inferred #const n=" << clingo_like_n_ << " from x/1\n";
        }
    }

    if (stats && use_prolog_query_backend_) {
        std::vector<std::string> relevant_sorted(relevant_predicates.begin(), relevant_predicates.end());
        std::sort(relevant_sorted.begin(), relevant_sorted.end());
        std::vector<std::string> ignored_sorted(ignored_signatures.begin(), ignored_signatures.end());
        std::sort(ignored_sorted.begin(), ignored_sorted.end());

        std::cerr << "[lazy-prolog] relevant predicates:";
        for (auto const &signature : relevant_sorted) {
            std::cerr << " " << signature;
        }
        std::cerr << "\n";
        std::cerr << "[lazy-prolog] symbolic atoms considered=" << considered_atoms
                  << " synchronized=" << (clingo_like_static_symbols_.size() + symbols_by_solver_lit_.size())
                  << " ignored_irrelevant=" << ignored_irrelevant_atoms << "\n";
        if (!ignored_sorted.empty()) {
            std::cerr << "[lazy-prolog] ignored signatures:";
            size_t const limit = std::min<size_t>(ignored_sorted.size(), 8);
            for (size_t i = 0; i < limit; ++i) {
                std::cerr << " " << ignored_sorted[i];
            }
            if (ignored_sorted.size() > limit) {
                std::cerr << " ...";
            }
            std::cerr << "\n";
        }
    }

    if (use_prolog_query_backend_ && !clingo_like_heuristic_rules_.empty()) {
        std::vector<Clingo::Symbol> known_atoms;
        known_atoms.reserve(symbols_by_solver_lit_.size());
        for (auto const &[lit, symbol] : symbols_by_solver_lit_) {
            add_solver_watch(init, lit);
            add_solver_watch(init, -lit);
            known_atoms.push_back(symbol);
        }
        std::sort(known_atoms.begin(), known_atoms.end(), [](Clingo::Symbol const &a, Clingo::Symbol const &b) {
            return a.to_string() < b.to_string();
        });

        query_backend_.reset(new SWIPrologHeuristicBackend());
        query_backend_->initialize(clingo_like_heuristic_rules_,
                                   clingo_like_static_symbols_,
                                   known_atoms,
                                   clingo_like_has_n_,
                                   clingo_like_n_);
        synchronize_query_backend_state(init.assignment());
    }
}

std::vector<std::string> HeuristicPropagator::build_dynamic_trail_facts(
    Clingo::Assignment const &assignment,
    HeuristicSemantics semantics
) const {
    std::vector<std::string> facts;
    facts.reserve(symbols_by_solver_lit_.size());

    for (auto const &[lit, symbol] : symbols_by_solver_lit_) {
        auto const value = assignment.truth_value(lit);
        if (value == Clingo::TruthValue::True) {
            facts.push_back(symbol_to_fact(symbol));
        }
        else if (value == Clingo::TruthValue::False ||
                 (semantics == HeuristicSemantics::Alpha && value == Clingo::TruthValue::Free)) {
            std::string false_fact = false_symbol_to_fact(symbol);
            if (!false_fact.empty()) {
                facts.push_back(std::move(false_fact));
            }
        }
    }

    std::sort(facts.begin(), facts.end());
    facts.erase(std::unique(facts.begin(), facts.end()), facts.end());
    return facts;
}

// Ordinamento condiviso dei candidati euristici (Prolog e clingo-like):
// priority decrescente, poi weight decrescente, poi tie-break deterministico.
// Ranked deve esporre .active{priority, weight, rule_index}, .target_string, .lit.
template <class Ranked>
static bool ranked_candidate_better(Ranked const &a, Ranked const &b) {
    if (a.active.priority != b.active.priority) {
        return a.active.priority > b.active.priority;
    }
    if (a.active.weight != b.active.weight) {
        return a.active.weight > b.active.weight;
    }
    if (a.target_string != b.target_string) {
        return a.target_string < b.target_string;
    }
    return a.lit < b.lit;
}

// Variante usata per scegliere il miglior candidato di uno stesso target:
// a parita' di (priority, weight) vince la regola dichiarata prima.
template <class Ranked>
static bool ranked_candidate_beats_best(Ranked const &candidate, Ranked const &best) {
    if (candidate.active.priority != best.active.priority) {
        return candidate.active.priority > best.active.priority;
    }
    if (candidate.active.weight != best.active.weight) {
        return candidate.active.weight > best.active.weight;
    }
    return candidate.active.rule_index < best.active.rule_index;
}

static std::unordered_set<std::string> collect_negated_predicate_signatures(
    std::vector<QueryHeuristicRule> const &rules
) {
    std::unordered_set<std::string> signatures;
    for (auto const &rule : rules) {
        std::string const normalized = trim_copy(rule.original_rule);
        collect_wrapper_argument_signatures(signatures, normalized, "clingo_not", 0);
        collect_wrapper_argument_signatures(signatures, normalized, "alpha_not", 0);
    }
    return signatures;
}

std::vector<HeuristicPropagator::ActiveHeuristic>
HeuristicPropagator::evaluate_active_heuristics_with_aux_clingo(
    std::vector<std::string> const &dynamic_facts,
    HeuristicSemantics semantics
) const {
    std::ostringstream program;
    if (clingo_like_has_n_) {
        program << "#const n=" << clingo_like_n_ << ".\n";
    }
    for (auto const &fact : clingo_like_static_facts_) {
        program << fact;
    }
    for (auto const &fact : dynamic_facts) {
        program << fact;
    }

    auto const negated_predicates = collect_negated_predicate_signatures(clingo_like_heuristic_rules_);
    for (auto const &sig_str : negated_predicates) {
        size_t slash = sig_str.find('/');
        if (slash == std::string::npos) continue;
        std::string name = sig_str.substr(0, slash);
        int arity = std::stoi(sig_str.substr(slash + 1));

        std::string args;
        if (arity > 0) {
            args += "(";
            for (int i = 0; i < arity; ++i) {
                if (i > 0) args += ",";
                args += "X" + std::to_string(i);
            }
            args += ")";
        }
        program << "clingo_not(" << name << args << ") :- not_" << name << args << ".\n";
        program << "alpha_not(" << name << args << ") :- not_" << name << args << ".\n";
    }

    for (auto const &rule : clingo_like_heuristic_rules_) {
        if (rule.semantics != semantics) continue;
        program << rule.normalized_rule << "\n";
    }
    program << "#show active_heuristic/4.\n";

    auto const program_string = program.str();
    if (lazy_heuristic_debug_enabled()) {
        std::cerr << "[lazy-heuristic] auxiliary program for "
                  << heuristic_semantics_name(semantics) << ":\n"
                  << program_string << "\n";
    }

    Clingo::Control ctl{{"0", "--warn=none"}, nullptr, 20};
    try {
        ctl.add("base", {}, program_string.c_str());
        ctl.ground({{"base", {}}});
    }
    catch (std::exception const &ex) {
        std::cerr << "[lazy-heuristic] auxiliary clingo failed for "
                  << heuristic_semantics_name(semantics) << ": " << ex.what() << "\n"
                  << "[lazy-heuristic] auxiliary program was:\n"
                  << program_string << "\n";
        throw;
    }

    std::vector<ActiveHeuristic> result;
    size_t emitted_index = 0;
    auto handle = ctl.solve();
    for (auto const &model : handle) {
        for (auto const &symbol : model.symbols()) {
            if (!symbol.match("active_heuristic", 4)) continue;

            auto const args = symbol.arguments();
            if (args.size() != 4 ||
                args[1].type() != Clingo::SymbolType::Number ||
                args[2].type() != Clingo::SymbolType::Number) {
                throw std::runtime_error("Lazy heuristic clingo-like: active_heuristic/4 must have numeric Weight and Priority.");
            }

            ActiveHeuristic active;
            active.target = args[0];
            active.weight = args[1].number();
            active.priority = args[2].number();
            active.semantics = semantics;
            active.rule_index = emitted_index;
            if (!parse_clingo_like_sign(args[3], active.sign)) {
                throw std::runtime_error("Lazy heuristic clingo-like: the fourth argument must be true or false.");
            }

            result.push_back(std::move(active));
            ++emitted_index;
        }
    }
    handle.get();
    return result;
}

Clingo::literal_t HeuristicPropagator::decide_with_clingo_like_heuristics(
    Clingo::Assignment const &assignment,
    Clingo::literal_t fallback
) const {
    static_cast<void>(fallback);

    std::vector<ActiveHeuristic> candidates;
    for (HeuristicSemantics semantics : {HeuristicSemantics::Alpha, HeuristicSemantics::Clingo}) {
        auto has_semantic_rules = std::any_of(
            clingo_like_heuristic_rules_.begin(),
            clingo_like_heuristic_rules_.end(),
            [semantics](QueryHeuristicRule const &rule) { return rule.semantics == semantics; }
        );
        if (!has_semantic_rules) continue;

        auto const dynamic_facts = build_dynamic_trail_facts(assignment, semantics);
        auto semantic_candidates = evaluate_active_heuristics_with_aux_clingo(dynamic_facts, semantics);
        candidates.insert(candidates.end(),
                          std::make_move_iterator(semantic_candidates.begin()),
                          std::make_move_iterator(semantic_candidates.end()));
    }

    struct RankedCandidate {
        ActiveHeuristic active;
        Clingo::literal_t lit = 0;
        std::string target_string;
    };

    std::unordered_map<std::string, RankedCandidate> best_by_target;
    for (auto const &candidate : candidates) {
        auto lit_it = solver_lit_by_symbol_.find(candidate.target);
        if (lit_it == solver_lit_by_symbol_.end()) {
            if (lazy_heuristic_debug_enabled()) {
                std::cerr << "[lazy-heuristic] discarding unmapped target "
                          << candidate.target << "\n";
            }
            continue;
        }

        Clingo::literal_t const lit = lit_it->second;
        if (lit == 0 || assignment.truth_value(lit) != Clingo::TruthValue::Free) continue;

        RankedCandidate ranked_candidate;
        ranked_candidate.active = candidate;
        ranked_candidate.lit = lit;
        ranked_candidate.target_string = candidate.target.to_string();

        auto current = best_by_target.find(ranked_candidate.target_string);
        if (current == best_by_target.end() ||
            ranked_candidate_beats_best(ranked_candidate, current->second)) {
            best_by_target[ranked_candidate.target_string] = std::move(ranked_candidate);
        }
    }

    if (best_by_target.empty()) return 0;

    std::vector<RankedCandidate> ranked;
    ranked.reserve(best_by_target.size());
    for (auto &entry : best_by_target) {
        ranked.push_back(std::move(entry.second));
    }
    std::sort(ranked.begin(), ranked.end(), ranked_candidate_better<RankedCandidate>);

    auto const &best = ranked.front();
    if (lazy_heuristic_debug_enabled()) {
        std::cerr << "[lazy-heuristic] decision target=" << best.active.target
                  << " weight=" << best.active.weight
                  << " local_priority=" << best.active.priority
                  << " sign=" << (best.active.sign ? "true" : "false")
                  << " semantics=" << heuristic_semantics_name(best.active.semantics)
                  << "\n";
    }
    return best.active.sign ? best.lit : -best.lit;
}

void HeuristicPropagator::synchronize_query_backend_state(Clingo::Assignment const &assignment) {
    if (!query_backend_) return;

    for (auto const &[lit, symbol] : symbols_by_solver_lit_) {
        QueryAtomState state = QueryAtomState::Free;
        if (assignment.is_true(lit)) {
            state = QueryAtomState::True;
        }
        else if (assignment.is_false(lit)) {
            state = QueryAtomState::False;
        }
        query_backend_->set_atom_state(symbol, state);
    }
}

void HeuristicPropagator::synchronize_query_backend_literal(Clingo::literal_t lit,
                                                            Clingo::Assignment const &assignment) noexcept {
    if (!query_backend_) return;

    bool const stats = lazy_prolog_stats_enabled();
    ScopedLazyStatsTimer sync_timer(stats, query_backend_stats_.total_state_sync_time_ms);

    try {
        auto synchronize_one = [this, &assignment](Clingo::literal_t solver_lit) {
            auto symbol_it = symbols_by_watched_solver_lit_.find(solver_lit);
            if (symbol_it == symbols_by_watched_solver_lit_.end()) return;

            QueryAtomState state = QueryAtomState::Free;
            if (assignment.is_true(solver_lit)) {
                state = QueryAtomState::True;
            }
            else if (assignment.is_false(solver_lit)) {
                state = QueryAtomState::False;
            }
            for (auto const &symbol : symbol_it->second) {
                query_backend_->set_atom_state(symbol, state);
            }
        };

        synchronize_one(lit);
        synchronize_one(-lit);
    }
    catch (std::exception const &ex) {
        std::cerr << "[lazy-prolog] synchronization failed: " << ex.what() << "\n";
    }
    catch (...) {
        std::cerr << "[lazy-prolog] synchronization failed with an unknown exception\n";
    }
}

Clingo::literal_t HeuristicPropagator::decide_with_query_backend(
    Clingo::Assignment const &assignment,
    Clingo::literal_t fallback
) {
    static_cast<void>(fallback);
    if (!query_backend_) return 0;

    bool const stats = lazy_prolog_stats_enabled();
    query_backend_stats_.used = true;
    ++query_backend_stats_.decide_calls;
    ScopedLazyStatsTimer decide_timer(stats, query_backend_stats_.total_decide_time_ms);

    // Full sync is redundant as state is kept in sync incrementally via propagate() and undo()
    // {
    //     ScopedLazyStatsTimer sync_timer(stats, query_backend_stats_.total_state_sync_time_ms);
    //     synchronize_query_backend_state(assignment);
    // }

    std::vector<QueryHeuristicCandidate> candidates;
    {
        ScopedLazyStatsTimer query_timer(stats, query_backend_stats_.total_prolog_query_time_ms);
        candidates = query_backend_->query_applicable_candidates();
    }
    if (stats) {
        query_backend_stats_.total_candidates_seen += candidates.size();
        query_backend_stats_.max_candidates_seen = std::max(query_backend_stats_.max_candidates_seen,
                                                            candidates.size());
    }

    struct RankedCandidate {
        QueryHeuristicCandidate active;
        Clingo::literal_t lit = 0;
        std::string target_string;
    };

    std::vector<RankedCandidate> ranked;
    ranked.reserve(candidates.size());
    size_t discarded_unmapped = 0;
    size_t discarded_assigned = 0;
    {
        ScopedLazyStatsTimer scan_timer(stats, query_backend_stats_.total_candidate_scan_time_ms);
        for (auto const &candidate : candidates) {
            LazyStatsClock::time_point literal_lookup_start;
            if (stats) {
                literal_lookup_start = LazyStatsClock::now();
            }
            auto lit_it = solver_lit_by_symbol_.find(candidate.target);
            if (lit_it == solver_lit_by_symbol_.end()) {
                if (stats) {
                    query_backend_stats_.total_literal_lookup_time_ms += elapsed_ms(literal_lookup_start);
                }
                ++discarded_unmapped;
                continue;
            }

            Clingo::literal_t const lit = lit_it->second;
            auto const value = assignment.truth_value(lit);
            if (stats) {
                query_backend_stats_.total_literal_lookup_time_ms += elapsed_ms(literal_lookup_start);
            }
            if (lit == 0 || value != Clingo::TruthValue::Free) {
                ++discarded_assigned;
                continue;
            }

            RankedCandidate ranked_candidate;
            ranked_candidate.active = candidate;
            ranked_candidate.lit = lit;
            ranked_candidate.target_string = candidate.target.to_string();
            ranked.push_back(std::move(ranked_candidate));
        }
    }

    if (stats || lazy_heuristic_debug_enabled()) {
        std::cerr << "[lazy-prolog] stats decide_call_id=" << query_backend_stats_.decide_calls
                  << " produced=" << candidates.size()
                  << " discarded_assigned=" << discarded_assigned
                  << " discarded_unmapped=" << discarded_unmapped
                  << " considered=" << ranked.size()
                  << "\n";
    }

    if (ranked.empty()) return 0;

    {
        ScopedLazyStatsTimer selection_timer(stats, query_backend_stats_.total_candidate_selection_time_ms);
        if (!lazy_prolog_alpha_query_ranking()) {
            std::unordered_map<std::string, RankedCandidate> best_by_target;
            for (auto &candidate : ranked) {
                auto current = best_by_target.find(candidate.target_string);
                if (current == best_by_target.end() ||
                    ranked_candidate_beats_best(candidate, current->second)) {
                    best_by_target[candidate.target_string] = std::move(candidate);
                }
            }

            ranked.clear();
            ranked.reserve(best_by_target.size());
            for (auto &entry : best_by_target) {
                ranked.push_back(std::move(entry.second));
            }
        }
        std::sort(ranked.begin(), ranked.end(), ranked_candidate_better<RankedCandidate>);
    }

    auto const &best = ranked.front();
    if (lazy_heuristic_debug_enabled()) {
        std::cerr << "[lazy-prolog] selected target=" << best.active.target
                  << " weight=" << best.active.weight
                  << " priority=" << best.active.priority
                  << " sign=" << (best.active.sign ? "true" : "false")
                  << " lit=" << best.lit
                  << " assignment.is_true(L)=" << (assignment.is_true(best.lit) ? "true" : "false")
                  << " assignment.is_false(L)=" << (assignment.is_false(best.lit) ? "true" : "false")
                  << "\n";
    }
    return best.active.sign ? best.lit : -best.lit;
}

HeuristicPropagator::~HeuristicPropagator() {
    print_query_backend_stats();
}

void HeuristicPropagator::print_query_backend_stats() const {
    if (!lazy_prolog_stats_enabled() || !query_backend_stats_.used) return;

    double const avg_candidates = query_backend_stats_.decide_calls == 0
        ? 0.0
        : static_cast<double>(query_backend_stats_.total_candidates_seen) /
              static_cast<double>(query_backend_stats_.decide_calls);

    std::cerr << "[lazy-prolog] summary"
              << " decide_calls=" << query_backend_stats_.decide_calls
              << " total_decide_time_ms=" << query_backend_stats_.total_decide_time_ms
              << " total_state_sync_time_ms=" << query_backend_stats_.total_state_sync_time_ms
              << " total_prolog_query_time_ms=" << query_backend_stats_.total_prolog_query_time_ms
              << " total_candidate_scan_time_ms=" << query_backend_stats_.total_candidate_scan_time_ms
              << " total_literal_lookup_time_ms=" << query_backend_stats_.total_literal_lookup_time_ms
              << " total_candidate_selection_time_ms=" << query_backend_stats_.total_candidate_selection_time_ms
              << " total_candidates_seen=" << query_backend_stats_.total_candidates_seen
              << " max_candidates_seen=" << query_backend_stats_.max_candidates_seen
              << " avg_candidates_per_decide=" << avg_candidates
              << "\n";
}




void HeuristicPropagator::add_solver_watch(Clingo::PropagateInit &init, Clingo::literal_t lit) {
    if (lit == 0) return;
    if (registered_watch_lits_.insert(lit).second) {
        init.add_watch(lit);
    }
}



































void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    auto assignment = control.assignment();

    for (auto lit : changes) {
        synchronize_query_backend_literal(lit, assignment);
    }
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    auto assignment = control.assignment();

    for (auto lit : changes) {
        synchronize_query_backend_literal(lit, assignment);
    }
}

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id,
                                               Clingo::Assignment const &assignment,
                                               Clingo::literal_t fallback) noexcept {
    static_cast<void>(thread_id);

    try {
        if (query_backend_) {
            return decide_with_query_backend(assignment, fallback);
        }

        if (!clingo_like_heuristic_rules_.empty()) {
            return decide_with_clingo_like_heuristics(assignment, fallback);
        }
    }
    catch (std::exception const &ex) {
        std::cerr << "[lazy-heuristic] decide failed: " << ex.what() << "\n";
        return 0;
    }
    catch (...) {
        std::cerr << "[lazy-heuristic] decide failed with an unknown exception\n";
        return 0;
    }

    return 0;
}
