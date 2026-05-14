#pragma once

#include "clingo/heuristic_aggregate.hh"
#include "clingo/heuristic_types.hh"
#include <clingo.hh>
#include <cstddef>
#include <memory>
#include <set>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

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
        Clingo::Symbol variable_name;
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
        std::unordered_map<Clingo::Symbol, int> body_var_values;
        std::vector<Clingo::literal_t> pos_body_lits;
        std::vector<Clingo::literal_t> neg_body_lits;
        std::vector<CandidateAggregateBinding> aggregate_bindings;
        bool queued = false;
        CandidateQueueEntry queue_entry;
    };

    struct LazyTemplatePredicateSets {
        std::unordered_set<Clingo::Symbol> pos_body_preds;
        std::unordered_set<Clingo::Symbol> target_preds;
        std::unordered_set<Clingo::Symbol> neg_preds;
    };

    using LitByTuple = std::unordered_map<AtomKey, Clingo::literal_t, AtomKeyHash>;
    using GroundLiteralIndex = std::unordered_map<Clingo::Symbol, LitByTuple>;

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
    LazyTemplatePredicateSets collect_predicates_used_by_lazy_templates() const;
    GroundLiteralIndex build_ground_literal_index_for_predicates(Clingo::PropagateInit &init,
                                                                 Clingo::SymbolicAtoms const &atoms,
                                                                 LazyTemplatePredicateSets const &predicates) const;
    void materialize_lazy_candidates_and_register_watches(Clingo::PropagateInit &init,
                                                          GroundLiteralIndex const &ground_literal_index);
    void register_lazy_aggregate_watches(Clingo::PropagateInit &init, Clingo::SymbolicAtoms const &atoms);
    AggregateState *ensure_aggregate_state(RuntimeAggregateKey const &runtime_key);
    void add_solver_watch(Clingo::PropagateInit &init, Clingo::literal_t lit);
    void register_candidate_refresh_watch(Clingo::PropagateInit &init, Clingo::literal_t lit, size_t candidate_id);
    void add_candidate_and_register_refresh_watches(Clingo::PropagateInit &init,
                                                    size_t rule_idx,
                                                    Clingo::literal_t target_lit,
                                                    std::vector<int> const &tuple_values,
                                                    std::vector<Clingo::literal_t> pos_body_lits,
                                                    std::vector<Clingo::literal_t> neg_body_lits,
                                                    std::unordered_map<Clingo::Symbol, int> body_var_values);
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
