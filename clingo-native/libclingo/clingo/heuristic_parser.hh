#pragma once

#include "clingo/heuristic_types.hh"
#include <clingo.hh>
#include <unordered_map>
#include <vector>

std::vector<HeuristicRuleTemplate> parse_lazy_heuristic_templates(std::vector<Clingo::Symbol> const &heuristic_symbols);

int evaluate_arithmetic_expression(ArithmeticExpression const &expr,
                                   int self_value,
                                   std::unordered_map<Clingo::Symbol, int> const &var_env);
