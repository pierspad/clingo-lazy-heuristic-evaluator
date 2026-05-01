#pragma once
#include <clingo.hh>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <string>
#include <memory>
#include <map>
#include <set>
#include <climits>
#include <utility>

// Stato incrementale di un aggregato dinamico.
// Il propagatore chiama add/remove seguendo trail e backtracking di clingo.
struct AggregateState {
    virtual ~AggregateState() = default;
    virtual void add(int value) = 0;
    virtual void remove(int value) = 0;
    virtual int result() const = 0;
    virtual void reset() = 0;
};

struct SumState final : AggregateState {
    int total = 0;
    void add(int v) override    { total += v; }
    void remove(int v) override { total -= v; }
    int result() const override { return total; }
    void reset() override       { total = 0; }
};

struct CountState final : AggregateState {
    int count = 0;
    void add(int) override      { ++count; }
    void remove(int) override   { --count; }
    int result() const override { return count; }
    void reset() override       { count = 0; }
};

struct MinState final : AggregateState {
    std::map<int, int> active;
    void add(int v) override    { active[v]++; }
    void remove(int v) override {
        auto it = active.find(v);
        if (it != active.end() && --(it->second) == 0) active.erase(it);
    }
    int result() const override {
        return active.empty() ? 0 : active.begin()->first;
    }
    void reset() override { active.clear(); }
};

struct MaxState final : AggregateState {
    std::map<int, int> active;
    void add(int v) override    { active[v]++; }
    void remove(int v) override {
        auto it = active.find(v);
        if (it != active.end() && --(it->second) == 0) active.erase(it);
    }
    int result() const override {
        return active.empty() ? 0 : active.rbegin()->first;
    }
    void reset() override { active.clear(); }
};

inline std::unique_ptr<AggregateState> make_aggregate(std::string const &op) {
    if (op == "__sum")   return std::make_unique<SumState>();
    if (op == "__count") return std::make_unique<CountState>();
    if (op == "__min")   return std::make_unique<MinState>();
    if (op == "__max")   return std::make_unique<MaxState>();
    return nullptr;
}

// Filtro opzionale per aggregati contestuali.
// Esempio: __filter(1, 0, -1) significa:
//   argomento 1 dell'atomo sorgente == argomento 0 del target - 1.
// Se la lista filtri e' vuota, l'aggregato resta globale come nella sintassi
// iniziale __sum(c, 0).
struct AggregateFilter {
    int source_arg_index = -1;
    int target_arg_index = -1;
    int target_offset = 0;

    bool operator==(AggregateFilter const &o) const {
        return source_arg_index == o.source_arg_index &&
               target_arg_index == o.target_arg_index &&
               target_offset == o.target_offset;
    }
};

struct AggregateKey {
    std::string op_name;
    std::string pred_name;
    int arg_index = -1;
    std::vector<AggregateFilter> filters;

    bool operator==(AggregateKey const &o) const {
        return op_name == o.op_name &&
               pred_name == o.pred_name &&
               arg_index == o.arg_index &&
               filters == o.filters;
    }
};

struct AggregateKeyHash {
    std::size_t operator()(AggregateKey const &k) const {
        std::size_t h = 17;
        h = h * 31 + std::hash<std::string>{}(k.op_name);
        h = h * 31 + std::hash<std::string>{}(k.pred_name);
        h = h * 31 + std::hash<int>{}(k.arg_index);
        for (auto const &filter : k.filters) {
            h = h * 31 + std::hash<int>{}(filter.source_arg_index);
            h = h * 31 + std::hash<int>{}(filter.target_arg_index);
            h = h * 31 + std::hash<int>{}(filter.target_offset);
        }
        return h;
    }
};

// Chiave completa dello stato aggregato a runtime.
// AggregateKey descrive "che cosa" aggregare; filter_values dice per quale
// tupla concreta del target (es. U, U-1, S, ...).
struct RuntimeAggregateKey {
    AggregateKey key;
    std::vector<int> filter_values;

    bool operator==(RuntimeAggregateKey const &o) const {
        return key == o.key && filter_values == o.filter_values;
    }
};

struct RuntimeAggregateKeyHash {
    std::size_t operator()(RuntimeAggregateKey const &k) const {
        std::size_t h = AggregateKeyHash{}(k.key);
        for (int value : k.filter_values) {
            h = h * 31 + std::hash<int>{}(value);
        }
        return h;
    }
};

// Tupla numerica usata per far combaciare target, body positivi e body negativi.
// Per BSP e' [X]; per PUP diventa [S,U] o [Z,U].
struct AtomKey {
    std::vector<int> values;

    bool operator==(AtomKey const &o) const {
        return values == o.values;
    }
};

struct AtomKeyHash {
    std::size_t operator()(AtomKey const &k) const {
        std::size_t h = 17;
        for (int value : k.values) {
            h = h * 31 + std::hash<int>{}(value);
        }
        return h;
    }
};

enum class HeuristicSign { True, False, FollowFallback };
enum class HeuristicSemantics { Alpha, Clingo };

struct BodyMatch {
    int source_arg_index = -1;
    int target_arg_index = -1;
};

struct BodyArgBinding {
    std::string variable_name;
    int source_arg_index = -1;
};

struct BodyPredicateSpec {
    std::string pred_name;
    std::vector<BodyMatch> matches;
    std::vector<BodyArgBinding> arg_bindings;
    bool explicit_mapping = false;
};

// AST minimale per __weight(...) e __priority(...).
// Dopo init non conserviamo piu' Clingo::Symbol: decide valuta solo questa
// rappresentazione tipizzata e gia' validata.
enum class ArithmeticExpressionKind {
    Number,
    Self,
    BoundVariable,
    Add,
    Sub,
    Mul
};

struct ArithmeticExpression {
    ArithmeticExpressionKind kind = ArithmeticExpressionKind::Number;
    int value = 0;
    std::string variable_name;
    std::unique_ptr<ArithmeticExpression> left;
    std::unique_ptr<ArithmeticExpression> right;

    static ArithmeticExpression number(int value) {
        ArithmeticExpression expr;
        expr.kind = ArithmeticExpressionKind::Number;
        expr.value = value;
        return expr;
    }

    static ArithmeticExpression self() {
        ArithmeticExpression expr;
        expr.kind = ArithmeticExpressionKind::Self;
        return expr;
    }

    static ArithmeticExpression bound_variable(std::string name) {
        ArithmeticExpression expr;
        expr.kind = ArithmeticExpressionKind::BoundVariable;
        expr.variable_name = std::move(name);
        return expr;
    }

    static ArithmeticExpression binary(ArithmeticExpressionKind kind,
                                       ArithmeticExpression lhs,
                                       ArithmeticExpression rhs) {
        ArithmeticExpression expr;
        expr.kind = kind;
        expr.left = std::make_unique<ArithmeticExpression>(std::move(lhs));
        expr.right = std::make_unique<ArithmeticExpression>(std::move(rhs));
        return expr;
    }
};

struct HeuristicRuleTemplate {
    std::string target_pred;
    std::vector<BodyPredicateSpec> pos_body_preds;
    std::vector<std::string> neg_body_preds;
    HeuristicSign sign = HeuristicSign::True;
    HeuristicSemantics semantics = HeuristicSemantics::Alpha;
    std::unordered_map<std::string, AggregateKey> var_bindings;
    std::unordered_set<std::string> body_var_names;
    ArithmeticExpression weight_expr = ArithmeticExpression::number(0);
    ArithmeticExpression priority_expr = ArithmeticExpression::number(0);
};

class HeuristicPropagator : public Clingo::Heuristic {

private:
    struct WatchedAtomContribution {
        RuntimeAggregateKey runtime_key;
        int value;
    };

    struct WatchedAtomInfo {
        std::vector<WatchedAtomContribution> contributions;
    };

    struct CandidateAggregateBinding {
        std::string variable_name;
        RuntimeAggregateKey runtime_key;
        bool valid_key = false;
    };

    struct CandidateQueueEntry {
        int priority = 0;
        int weight = 0;
        Clingo::literal_t target_lit = 0;
        size_t candidate_id = 0;

        bool operator==(CandidateQueueEntry const &o) const {
            return priority == o.priority &&
                   weight == o.weight &&
                   target_lit == o.target_lit &&
                   candidate_id == o.candidate_id;
        }
    };

    struct CandidateQueueEntryLess {
        bool operator()(CandidateQueueEntry const &a, CandidateQueueEntry const &b) const {
            if (a.priority != b.priority) return a.priority > b.priority;
            if (a.weight != b.weight) return a.weight > b.weight;
            if (a.target_lit != b.target_lit) return a.target_lit < b.target_lit;
            return a.candidate_id < b.candidate_id;
        }
    };

    struct CandidateState {
        size_t rule_idx = 0;
        Clingo::literal_t target_lit = 0;
        int self_value = 0;
        std::vector<int> tuple_values;
        std::unordered_map<std::string, int> body_var_values;
        std::vector<Clingo::literal_t> pos_body_lits;
        std::vector<Clingo::literal_t> neg_body_lits;
        std::vector<CandidateAggregateBinding> aggregate_bindings;
        bool queued = false;
        CandidateQueueEntry queue_entry;
    };

    struct RulePredicateSets {
        std::unordered_set<std::string> body_preds;
        std::unordered_set<std::string> target_preds;
        std::unordered_set<std::string> neg_preds;
    };

    using LitByTuple = std::unordered_map<AtomKey, Clingo::literal_t, AtomKeyHash>;
    using PredLitMap = std::unordered_map<std::string, LitByTuple>;

    std::unordered_map<Clingo::literal_t, WatchedAtomInfo> watched_atoms_;
    std::vector<HeuristicRuleTemplate> rule_templates_;
    std::vector<CandidateState> candidates_;
    std::set<CandidateQueueEntry, CandidateQueueEntryLess> candidate_queue_;
    std::unordered_map<Clingo::literal_t, std::vector<size_t>> candidate_refresh_lits_;
    std::unordered_map<RuntimeAggregateKey, std::vector<size_t>, RuntimeAggregateKeyHash> aggregate_candidates_;
    std::unordered_map<RuntimeAggregateKey, std::unique_ptr<AggregateState>, RuntimeAggregateKeyHash> aggregate_states_;
    std::unordered_map<RuntimeAggregateKey, std::vector<Clingo::literal_t>, RuntimeAggregateKeyHash> aggregate_source_lits_;
    std::unordered_set<Clingo::literal_t> registered_watches_;

    void init_lazy_mode(Clingo::PropagateInit &init);
    void parse_lazy_heuristic_templates(Clingo::SymbolicAtoms const &atoms);
    RulePredicateSets extract_lazy_predicate_sets() const;
    PredLitMap build_lazy_predicate_literal_map(Clingo::PropagateInit &init,
                                                Clingo::SymbolicAtoms const &atoms,
                                                RulePredicateSets const &predicates) const;
    void register_lazy_body_triggers(Clingo::PropagateInit &init, PredLitMap const &pred_lit_map);
    void register_lazy_aggregate_watches(Clingo::PropagateInit &init, Clingo::SymbolicAtoms const &atoms);
    void add_solver_watch(Clingo::PropagateInit &init, Clingo::literal_t lit);
    void register_candidate_refresh_watch(Clingo::PropagateInit &init, Clingo::literal_t lit, size_t candidate_id);
    void add_candidate(Clingo::PropagateInit &init,
                       size_t rule_idx,
                       Clingo::literal_t target_lit,
                       std::vector<int> const &tuple_values,
                       std::vector<Clingo::literal_t> pos_body_lits,
                       std::vector<Clingo::literal_t> neg_body_lits,
                       std::unordered_map<std::string, int> body_var_values);
    void erase_candidate_from_queue(size_t candidate_id) noexcept;
    bool compute_candidate_entry(size_t candidate_id, Clingo::Assignment const &assignment,
                                 CandidateQueueEntry &entry) const;
    void refresh_candidate(size_t candidate_id, Clingo::Assignment const &assignment);
    void refresh_candidate_noexcept(size_t candidate_id, Clingo::Assignment const &assignment) noexcept;
    void refresh_candidates_for_literal(Clingo::literal_t lit, Clingo::Assignment const &assignment);
    void refresh_candidates_for_literal_noexcept(Clingo::literal_t lit, Clingo::Assignment const &assignment) noexcept;
    void refresh_candidates_for_aggregate(RuntimeAggregateKey const &runtime_key, Clingo::Assignment const &assignment);
    void refresh_candidates_for_aggregate_noexcept(RuntimeAggregateKey const &runtime_key,
                                                   Clingo::Assignment const &assignment) noexcept;
    void refresh_all_candidates(Clingo::Assignment const &assignment);

public:
    ~HeuristicPropagator() override = default;

    void init(Clingo::PropagateInit &init) override;
    void propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) override;
    void undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept override;
    Clingo::literal_t decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) noexcept override;
};
