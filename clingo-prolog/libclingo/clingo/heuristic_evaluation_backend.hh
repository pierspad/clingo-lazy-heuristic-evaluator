#pragma once

#include "clingo/heuristic_types.hh"
#include <clingo.hh>
#include <string>
#include <vector>

enum class QueryAtomState {
    Free,
    True,
    False
};

struct QueryHeuristicRule {
    HeuristicSemantics semantics = HeuristicSemantics::Alpha;
    std::string original_rule;
    std::string normalized_rule;
    std::string prolog_rule;
};

struct QueryHeuristicCandidate {
    Clingo::Symbol target;
    int weight = 0;
    int priority = 0;
    bool sign = true;
    HeuristicSemantics semantics = HeuristicSemantics::Alpha;
    size_t rule_index = 0;
};

class HeuristicEvaluationBackend {
public:
    virtual ~HeuristicEvaluationBackend() = default;

    virtual void initialize(std::vector<QueryHeuristicRule> const &rules,
                            std::vector<Clingo::Symbol> const &static_atoms,
                            std::vector<Clingo::Symbol> const &known_atoms,
                            bool has_n,
                            int n_value) = 0;
    virtual void set_atom_state(Clingo::Symbol const &atom, QueryAtomState state) = 0;
    virtual std::vector<QueryHeuristicCandidate> query_applicable_candidates() = 0;
};

