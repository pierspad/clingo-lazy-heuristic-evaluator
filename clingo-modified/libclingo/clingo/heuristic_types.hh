#pragma once

#include <clingo.hh>
#include <cstddef>
#include <functional>
#include <memory>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

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
    Clingo::Symbol op_symbol;
    Clingo::Symbol pred_symbol;
    int arg_index = -1;
    std::vector<AggregateFilter> filters;

    bool operator==(AggregateKey const &o) const {
        return op_symbol == o.op_symbol &&
               pred_symbol == o.pred_symbol &&
               arg_index == o.arg_index &&
               filters == o.filters;
    }
};

struct AggregateKeyHash {
    std::size_t operator()(AggregateKey const &k) const {
        std::size_t h = 17;
        h = h * 31 + std::hash<Clingo::Symbol>{}(k.op_symbol);
        h = h * 31 + std::hash<Clingo::Symbol>{}(k.pred_symbol);
        h = h * 31 + std::hash<int>{}(k.arg_index);
        for (auto const &filter : k.filters) {
            h = h * 31 + std::hash<int>{}(filter.source_arg_index);
            h = h * 31 + std::hash<int>{}(filter.target_arg_index);
            h = h * 31 + std::hash<int>{}(filter.target_offset);
        }
        return h;
    }
};

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

struct NumericTupleKey {
    std::vector<int> values;

    bool operator==(NumericTupleKey const &o) const {
        return values == o.values;
    }
};

struct NumericTupleKeyHash {
    std::size_t operator()(NumericTupleKey const &k) const {
        std::size_t h = 17;
        for (int value : k.values) {
            h = h * 31 + std::hash<int>{}(value);
        }
        return h;
    }
};

enum class HeuristicSign {
    True,
    False,
    FollowFallback
};

enum class HeuristicSemantics {
    Alpha,
    Clingo
};

struct BodyMatch {
    int source_arg_index = -1;
    int target_arg_index = -1;
};

struct BodyArgBinding {
    Clingo::Symbol variable_name;
    int source_arg_index = -1;
};

struct BodyPredicateSpec {
    Clingo::Symbol pred_name;
    std::vector<BodyMatch> matches;
    std::vector<BodyArgBinding> arg_bindings;
    bool explicit_mapping = false;
};

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
    Clingo::Symbol variable_name;
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

    static ArithmeticExpression bound_variable(Clingo::Symbol name) {
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
    Clingo::Symbol target_pred;
    std::vector<BodyPredicateSpec> pos_body_preds;
    std::vector<Clingo::Symbol> neg_body_preds;
    HeuristicSign sign = HeuristicSign::True;
    HeuristicSemantics semantics = HeuristicSemantics::Alpha;
    std::unordered_map<Clingo::Symbol, AggregateKey> var_bindings;
    std::unordered_set<Clingo::Symbol> body_var_names;
    ArithmeticExpression weight_expr = ArithmeticExpression::number(0);
    ArithmeticExpression priority_expr = ArithmeticExpression::number(0);
};
