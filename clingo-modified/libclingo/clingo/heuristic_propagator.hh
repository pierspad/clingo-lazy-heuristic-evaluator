#pragma once
#include <clingo.hh>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <string>
#include <memory>
#include <map>
#include <climits>

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
        return active.empty() ? INT_MAX : active.begin()->first;
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
        return active.empty() ? INT_MIN : active.rbegin()->first;
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

struct AggregateKey {
    std::string op_name;
    std::string pred_name;
    int arg_index = -1;

    bool operator==(AggregateKey const &o) const {
        return op_name == o.op_name && pred_name == o.pred_name && arg_index == o.arg_index;
    }
};

struct AggregateKeyHash {
    std::size_t operator()(AggregateKey const &k) const {
        std::size_t h = 17;
        h = h * 31 + std::hash<std::string>{}(k.op_name);
        h = h * 31 + std::hash<std::string>{}(k.pred_name);
        h = h * 31 + std::hash<int>{}(k.arg_index);
        return h;
    }
};

enum class HeuristicSign { True, False, FollowFallback };

struct HeuristicRuleTemplate {
    std::string target_pred;
    std::vector<std::string> pos_body_preds;
    std::vector<std::string> neg_body_preds;
    HeuristicSign sign = HeuristicSign::True;
    std::unordered_map<std::string, AggregateKey> var_bindings;
    Clingo::Symbol weight_term;
    Clingo::Symbol priority_term;
};

struct LazyTargetInstance {
    Clingo::literal_t target_lit;
    int domain_value;
    size_t rule_idx;
    size_t trigger_index;
};

class HeuristicPropagator : public Clingo::Heuristic {

private:
    struct WatchedAtomContribution {
        AggregateKey key;
        int value;
    };

    struct WatchedAtomInfo {
        std::vector<WatchedAtomContribution> contributions;
    };

    struct BodyTriggerInfo {
        size_t rule_idx;
        int domain_value;
        Clingo::literal_t target_lit;
        std::vector<Clingo::literal_t> neg_body_lits;
    };

    std::unordered_map<Clingo::literal_t, WatchedAtomInfo> watched_atoms_;
    std::vector<HeuristicRuleTemplate> rule_templates_;
    std::unordered_map<Clingo::literal_t, std::vector<BodyTriggerInfo>> body_triggers_;
    std::unordered_map<Clingo::literal_t, std::vector<LazyTargetInstance>> lazy_targets_;
    std::unordered_set<Clingo::literal_t> active_body_lits_;
    std::unordered_map<AggregateKey, std::unique_ptr<AggregateState>, AggregateKeyHash> aggregate_states_;

    void init_lazy_mode(Clingo::PropagateInit &init);

public:
    ~HeuristicPropagator() override = default;

    void init(Clingo::PropagateInit &init) override;
    void propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) override;
    void undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept override;
    Clingo::literal_t decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) noexcept override;
};