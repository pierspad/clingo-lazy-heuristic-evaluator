#pragma once

#include "clingo/heuristic_evaluation_backend.hh"
#include "clingo/heuristic_types.hh"
#include <clingo.hh>
#include <cstddef>
#include <memory>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class HeuristicPropagator : public Clingo::Heuristic {

private:
    struct ActiveHeuristic {
        Clingo::Symbol target;
        int weight = 0;
        int priority = 0;
        bool sign = true;
        HeuristicSemantics semantics = HeuristicSemantics::Alpha;
        size_t rule_index = 0;
    };

    struct QueryBackendStats {
        bool used = false;
        size_t decide_calls = 0;
        double total_decide_time_ms = 0.0;
        double total_state_sync_time_ms = 0.0;
        double total_prolog_query_time_ms = 0.0;
        double total_candidate_scan_time_ms = 0.0;
        double total_literal_lookup_time_ms = 0.0;
        double total_candidate_selection_time_ms = 0.0;
        size_t total_candidates_seen = 0;
        size_t max_candidates_seen = 0;
    };

    std::vector<QueryHeuristicRule> clingo_like_heuristic_rules_;
    std::vector<std::string> clingo_like_static_facts_;
    std::vector<Clingo::Symbol> clingo_like_static_symbols_;
    std::unordered_map<Clingo::Symbol, Clingo::literal_t> solver_lit_by_symbol_;
    std::unordered_map<Clingo::literal_t, std::vector<Clingo::Symbol>> symbols_by_watched_solver_lit_;
    std::vector<std::pair<Clingo::literal_t, Clingo::Symbol>> symbols_by_solver_lit_;
    std::unordered_set<Clingo::literal_t> registered_watch_lits_;
    std::unique_ptr<HeuristicEvaluationBackend> query_backend_;
    QueryBackendStats query_backend_stats_;
    bool use_prolog_query_backend_ = false;
    bool clingo_like_has_n_ = false;
    int clingo_like_n_ = 0;

    void init_clingo_like_mode(Clingo::PropagateInit &init, Clingo::SymbolicAtoms const &atoms);
    std::vector<std::string> build_dynamic_trail_facts(Clingo::Assignment const &assignment,
                                                       HeuristicSemantics semantics) const;
    std::vector<ActiveHeuristic> evaluate_active_heuristics_with_aux_clingo(
        std::vector<std::string> const &dynamic_facts,
        HeuristicSemantics semantics
    ) const;
    Clingo::literal_t decide_with_clingo_like_heuristics(Clingo::Assignment const &assignment,
                                                         Clingo::literal_t fallback) const;
    Clingo::literal_t decide_with_query_backend(Clingo::Assignment const &assignment,
                                                Clingo::literal_t fallback);
    void synchronize_query_backend_state(Clingo::Assignment const &assignment);
    void synchronize_query_backend_literal(Clingo::literal_t lit, Clingo::Assignment const &assignment) noexcept;
    void add_solver_watch(Clingo::PropagateInit &init, Clingo::literal_t lit);
    void print_query_backend_stats() const;

public:
    ~HeuristicPropagator() override;

    void init(Clingo::PropagateInit &init) override;
    void propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) override;
    void undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept override;
    Clingo::literal_t decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) noexcept override;
};
