#pragma once

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
    std::string variable_name;
    int source_arg_index = -1;
};

struct BodyPredicateSpec {
    std::string pred_name;
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
