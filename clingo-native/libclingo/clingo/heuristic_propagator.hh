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
    struct AggregateContribution {
        RuntimeAggregateKey runtime_key;
        int value;
    };

    struct AggregateContributions {
        std::vector<AggregateContribution> values;
    };

    struct CandidateAggregateBinding {
        Clingo::Symbol variable_name;
        RuntimeAggregateKey runtime_key;
        bool has_valid_runtime_key = false;
    };

    struct CandidateHeuristicEffect {
        bool active = false;
        Clingo::literal_t target_lit = 0;
        int bias = 0;
        HeuristicModifier modifier = HeuristicModifier::True;
        HeuristicSemantics semantics = HeuristicSemantics::Clingo;
        size_t candidate_id = 0;
    };

    // rank_weight e' il criterio di ordinamento, cioe' la forza del candidato;
    // value e' cio' che lo slot memorizza. Per `level` i due coincidono col
    // peso, per `sign` no: li' value e' la direzione (+1/-1) e rank_weight e'
    // il modulo del peso. E' un long long perche' il modulo di INT_MIN non e'
    // rappresentabile come int.
    struct ResolvedModifierValue {
        bool active = false;
        long long rank_weight = 0;
        int value = 0;
        size_t source_candidate_id = 0;
    };

    struct TargetHeuristicState {
        Clingo::literal_t target_lit = 0;
        ResolvedModifierValue level;
        ResolvedModifierValue sign;
        bool decision_active = false;
        int decision_weight = 0;
        bool decision_ranked = false;
        int ranked_weight = 0;
    };

    struct DecisionRankKey {
        int weight = 0;
        Clingo::literal_t target_lit = 0;
    };

    struct RuntimeHeuristicCandidate {
        size_t rule_idx = 0;
        Clingo::literal_t target_lit = 0;
        int self_value = 0;
        std::vector<int> tuple_values;
        std::unordered_map<Clingo::Symbol, int> body_var_values;
        std::vector<Clingo::literal_t> pos_body_lits;
        std::vector<Clingo::literal_t> neg_body_lits;
        std::vector<CandidateAggregateBinding> aggregate_bindings;
    };

    struct DecisionRankGreater {
        bool operator()(DecisionRankKey const &a, DecisionRankKey const &b) const {
            if (a.weight != b.weight) return a.weight > b.weight;
            return a.target_lit < b.target_lit;
        }
    };

    using LitByTuple = std::unordered_map<NumericTupleKey, Clingo::literal_t, NumericTupleKeyHash>;
    using GroundLiteralIndex = std::unordered_map<Clingo::Symbol, LitByTuple>;

    // Contatori del propagatore, gemelli di QueryBackendStats del backend
    // prolog: stessi nomi, cosi' il resultparser e i grafici confrontano i due
    // backend sulla stessa metrica invece di avere misure "solo prolog".
    // Attivi solo con LAZY_HEURISTIC_STATS/LAZY_PROLOG_STATS.
    //   decide_calls / total_decide_time_ms   -> costo del decidere (ms/decide)
    //   total_state_sync_time_ms              -> refresh incrementale in
    //                                            propagate()+undo(): qui e' il
    //                                            mantenimento in memoria degli
    //                                            aggregati, la' la sync verso SWI
    //   total_candidate_scan_time_ms          -> scansione della coda di rank
    //   *_candidates_seen                     -> entry esaminate per decisione
    // Non esiste un analogo di total_prolog_query_time_ms: nel backend native
    // non c'e' motore esterno da interrogare (differenza reale, non lacuna).
    struct LazyPropagatorStats {
        bool used = false;
        size_t decide_calls = 0;
        size_t decide_hits = 0;
        double total_decide_time_ms = 0.0;
        double total_state_sync_time_ms = 0.0;
        double total_candidate_scan_time_ms = 0.0;
        size_t total_candidates_seen = 0;
        size_t max_candidates_seen = 0;
        size_t propagate_calls = 0;
        size_t undo_calls = 0;
    };

    std::vector<HeuristicRuleTemplate> heuristic_rule_templates_;
    std::vector<RuntimeHeuristicCandidate> heuristic_candidates_;
    std::vector<CandidateHeuristicEffect> candidate_effects_;
    std::unordered_map<Clingo::literal_t, std::vector<size_t>> candidate_ids_by_target_;
    std::unordered_map<Clingo::literal_t, TargetHeuristicState> target_states_;
    std::set<DecisionRankKey, DecisionRankGreater> active_decision_ranks_;
    std::unordered_map<Clingo::literal_t, AggregateContributions> aggregate_contributions_by_lit_;
    std::unordered_map<Clingo::literal_t, std::vector<size_t>> candidate_ids_to_refresh_by_lit_;
    std::unordered_map<Clingo::literal_t, std::vector<RuntimeAggregateKey>> aggregate_keys_to_refresh_by_lit_;
    std::unordered_map<RuntimeAggregateKey, std::vector<size_t>, RuntimeAggregateKeyHash> candidate_ids_by_aggregate_;
    std::unordered_set<RuntimeAggregateKey, RuntimeAggregateKeyHash> aggregates_requiring_complete_sources_;
    std::unordered_map<RuntimeAggregateKey, std::unique_ptr<AggregateState>, RuntimeAggregateKeyHash> runtime_aggregate_states_;
    std::unordered_map<RuntimeAggregateKey, std::vector<Clingo::literal_t>, RuntimeAggregateKeyHash> aggregate_source_lits_;
    std::unordered_set<Clingo::literal_t> registered_watch_lits_;
    LazyPropagatorStats stats_;

    void init_lazy_mode(Clingo::PropagateInit &init,
                        Clingo::SymbolicAtoms const &atoms,
                        std::vector<HeuristicRuleTemplate> rule_templates);
    std::unordered_set<Clingo::Symbol> collect_predicates_used_by_lazy_templates() const;
    GroundLiteralIndex build_ground_literal_index_for_predicates(Clingo::PropagateInit &init,
                                                                 Clingo::SymbolicAtoms const &atoms) const;
    void materialize_lazy_candidates_and_register_watches(Clingo::PropagateInit &init,
                                                          GroundLiteralIndex const &ground_literal_index);
    void materialize_candidates_for_template(Clingo::PropagateInit &init,
                                             size_t rule_idx,
                                             GroundLiteralIndex const &ground_literal_index);
    std::unordered_map<Clingo::Symbol, std::vector<AggregateKey>> collect_aggregate_keys_by_source_predicate() const;
    void initialize_aggregate_sources(Clingo::PropagateInit &init, Clingo::SymbolicAtoms const &atoms);
    void initialize_aggregate_source_atom(Clingo::PropagateInit &init,
                                          Clingo::Assignment const &assignment,
                                          Clingo::Symbol const &source_symbol,
                                          Clingo::literal_t source_lit,
                                          AggregateKey const &aggregate_key);
    void watch_literal_for_aggregate_refresh(Clingo::PropagateInit &init,
                                             Clingo::literal_t lit,
                                             RuntimeAggregateKey const &runtime_key);
    bool aggregate_requires_complete_sources(RuntimeAggregateKey const &runtime_key) const;
    AggregateState *ensure_aggregate_state(RuntimeAggregateKey const &runtime_key);
    void add_solver_watch(Clingo::PropagateInit &init, Clingo::literal_t lit);
    void watch_literal_for_candidate_refresh(Clingo::PropagateInit &init, Clingo::literal_t lit, size_t candidate_id);
    RuntimeHeuristicCandidate build_runtime_candidate(size_t rule_idx,
                                                      Clingo::literal_t target_lit,
                                                      std::vector<int> const &tuple_values,
                                                      std::vector<Clingo::literal_t> pos_body_lits,
                                                      std::vector<Clingo::literal_t> neg_body_lits,
                                                      std::unordered_map<Clingo::Symbol, int> body_var_values) const;
    size_t store_runtime_candidate(RuntimeHeuristicCandidate candidate);
    void index_candidate_aggregate_dependencies(size_t candidate_id);
    void watch_candidate_refresh_literals(Clingo::PropagateInit &init, size_t candidate_id);
    void add_runtime_candidate(Clingo::PropagateInit &init,
                               size_t rule_idx,
                               Clingo::literal_t target_lit,
                               std::vector<int> const &tuple_values,
                               std::vector<Clingo::literal_t> pos_body_lits,
                               std::vector<Clingo::literal_t> neg_body_lits,
                               std::unordered_map<Clingo::Symbol, int> body_var_values);
    void erase_target_decision_rank(Clingo::literal_t target_lit) noexcept;
    bool candidate_target_is_free(RuntimeHeuristicCandidate const &candidate,
                                  Clingo::Assignment const &assignment) const;
    bool positive_body_is_satisfied(RuntimeHeuristicCandidate const &candidate,
                                    Clingo::Assignment const &assignment) const;
    bool negative_body_is_satisfied(HeuristicRuleTemplate const &tmpl,
                                    RuntimeHeuristicCandidate const &candidate,
                                    Clingo::Assignment const &assignment) const;
    bool aggregate_sources_are_determined(RuntimeAggregateKey const &runtime_key,
                                          Clingo::Assignment const &assignment) const;
    bool build_variable_environment(HeuristicRuleTemplate const &tmpl,
                                    RuntimeHeuristicCandidate const &candidate,
                                    Clingo::Assignment const &assignment,
                                    std::unordered_map<Clingo::Symbol, int> &var_env) const;
    bool evaluate_candidate_effect(size_t candidate_id,
                                   Clingo::Assignment const &assignment,
                                   CandidateHeuristicEffect &effect) const;
    void update_best_by_weight(ResolvedModifierValue &current,
                               long long rank_weight,
                               int value,
                               size_t candidate_id) const;
    void apply_effect_to_target_state(CandidateHeuristicEffect const &effect,
                                      TargetHeuristicState &state) const;
    Clingo::literal_t apply_resolved_sign(ResolvedModifierValue const &sign,
                                          Clingo::literal_t target_lit,
                                          Clingo::literal_t fallback) const;
    void refresh_target(Clingo::literal_t target_lit, Clingo::Assignment const &assignment);
    void refresh_candidate(size_t candidate_id, Clingo::Assignment const &assignment);
    void refresh_candidate_noexcept(size_t candidate_id, Clingo::Assignment const &assignment) noexcept;
    void refresh_aggregates_for_literal(Clingo::literal_t lit, Clingo::Assignment const &assignment);
    void refresh_aggregates_for_literal_noexcept(Clingo::literal_t lit,
                                                 Clingo::Assignment const &assignment) noexcept;
    void refresh_candidates_for_literal(Clingo::literal_t lit, Clingo::Assignment const &assignment);
    void refresh_candidates_for_literal_noexcept(Clingo::literal_t lit, Clingo::Assignment const &assignment) noexcept;
    void refresh_candidates_for_aggregate(RuntimeAggregateKey const &runtime_key, Clingo::Assignment const &assignment);
    void refresh_candidates_for_aggregate_noexcept(RuntimeAggregateKey const &runtime_key,
                                                   Clingo::Assignment const &assignment) noexcept;
    void refresh_all_candidates(Clingo::Assignment const &assignment);
    void print_propagator_stats() const;

public:
    ~HeuristicPropagator() override;

    void init(Clingo::PropagateInit &init) override;
    void propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) override;
    void undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept override;
    Clingo::literal_t decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) noexcept override;
};
