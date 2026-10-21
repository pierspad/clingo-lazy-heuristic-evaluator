#pragma once

#include "clingo/heuristic_evaluation_backend.hh"

#include <memory>

class SWIPrologHeuristicBackend : public HeuristicEvaluationBackend {
public:
    SWIPrologHeuristicBackend();
    ~SWIPrologHeuristicBackend() override;

    void initialize(std::vector<QueryHeuristicRule> const &rules,
                    std::vector<Clingo::Symbol> const &static_atoms,
                    std::vector<Clingo::Symbol> const &known_atoms,
                    bool has_n,
                    int n_value) override;
    void set_atom_state(Clingo::Symbol const &atom, QueryAtomState state) override;
    std::vector<QueryHeuristicCandidate> query_applicable_candidates() override;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

