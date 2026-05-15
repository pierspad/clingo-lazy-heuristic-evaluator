#include "clingo/heuristic_parser.hh"
#include "clingo/heuristic_symbol.hh"

#include <stdexcept>
#include <unordered_set>
#include <utility>

static bool is_neg_body(std::string const &name) {
    return name.size() > 4 && name.compare(0, 4, "__n_") == 0;
}

static bool try_parse_sign(std::string const &name, HeuristicSign &out) {
    if (name == "true") {
        out = HeuristicSign::True;
        return true;
    }
    if (name == "false") {
        out = HeuristicSign::False;
        return true;
    }
    if (name == "sign") {
        out = HeuristicSign::FollowFallback;
        return true;
    }
    return false;
}

static bool try_parse_semantics(std::string const &name, HeuristicSemantics &out) {
    if (name == "alpha") {
        out = HeuristicSemantics::Alpha;
        return true;
    }
    if (name == "clingo") {
        out = HeuristicSemantics::Clingo;
        return true;
    }
    return false;
}

static std::string strip_neg_prefix(std::string const &name) {
    return name.substr(4);
}

enum class ArithmeticOperator {
    Add,
    Sub,
    Mul,
    Unknown
};

static ArithmeticOperator parse_arithmetic_operator(std::string const &name) {
    if (name == "__add") {
        return ArithmeticOperator::Add;
    }
    if (name == "__sub") {
        return ArithmeticOperator::Sub;
    }
    if (name == "__mul") {
        return ArithmeticOperator::Mul;
    }
    return ArithmeticOperator::Unknown;
}

static ArithmeticExpressionKind expression_kind_for_operator(ArithmeticOperator op) {
    switch (op) {
        case ArithmeticOperator::Add:
            return ArithmeticExpressionKind::Add;
        case ArithmeticOperator::Sub:
            return ArithmeticExpressionKind::Sub;
        case ArithmeticOperator::Mul:
            return ArithmeticExpressionKind::Mul;
        case ArithmeticOperator::Unknown:
            break;
    }
    return ArithmeticExpressionKind::Number;
}

static ArithmeticExpression parse_arithmetic_expression(
    Clingo::Symbol const &term,
    std::unordered_map<Clingo::Symbol, AggregateKey> const &bindings,
    std::unordered_set<Clingo::Symbol> const &body_vars,
    std::string const &field_name
) {
    if (is_clingo_symbol_number(term)) {
        return ArithmeticExpression::number(term.number());
    }

    if (!is_clingo_symbol_function(term)) {
        throw std::runtime_error("Sintassi euristica malformata: " + field_name +
                                 " accetta solo numeri, self, variabili __bind e __add/__sub/__mul.");
    }

    std::string const name = term.name();
    Clingo::Symbol const name_symbol = term;
    auto const args = term.arguments();

    if (args.empty()) {
        if (name == "self") {
            return ArithmeticExpression::self();
        }
        if (bindings.find(name_symbol) != bindings.end()) {
            return ArithmeticExpression::bound_variable(name_symbol);
        }
        if (body_vars.find(name_symbol) != body_vars.end()) {
            return ArithmeticExpression::bound_variable(name_symbol);
        }
        throw std::runtime_error("Sintassi euristica malformata: variabile '" + name +
                                 "' usata in " + field_name + " ma non definita con __bind o __bind_arg.");
    }

    ArithmeticOperator const op = parse_arithmetic_operator(name);
    if (op == ArithmeticOperator::Unknown) {
        throw std::runtime_error("Sintassi euristica malformata: operatore '" + name +
                                 "' non valido in " + field_name + ".");
    }
    if (args.size() != 2) {
        throw std::runtime_error("Sintassi euristica malformata: operatore '" + name +
                                 "' in " + field_name + " richiede esattamente due argomenti.");
    }

    auto lhs = parse_arithmetic_expression(args[0], bindings, body_vars, field_name);
    auto rhs = parse_arithmetic_expression(args[1], bindings, body_vars, field_name);
    return ArithmeticExpression::binary(expression_kind_for_operator(op), std::move(lhs), std::move(rhs));
}

int evaluate_arithmetic_expression(
    ArithmeticExpression const &expr,
    int self_value,
    std::unordered_map<Clingo::Symbol, int> const &var_env
) {
    switch (expr.kind) {
        case ArithmeticExpressionKind::Number:
            return expr.value;
        case ArithmeticExpressionKind::Self:
            return self_value;
        case ArithmeticExpressionKind::BoundVariable: {
            auto it = var_env.find(expr.variable_name);
            return it != var_env.end() ? it->second : 0;
        }
        case ArithmeticExpressionKind::Add:
            return evaluate_arithmetic_expression(*expr.left, self_value, var_env) +
                   evaluate_arithmetic_expression(*expr.right, self_value, var_env);
        case ArithmeticExpressionKind::Sub:
            return evaluate_arithmetic_expression(*expr.left, self_value, var_env) -
                   evaluate_arithmetic_expression(*expr.right, self_value, var_env);
        case ArithmeticExpressionKind::Mul:
            return evaluate_arithmetic_expression(*expr.left, self_value, var_env) *
                   evaluate_arithmetic_expression(*expr.right, self_value, var_env);
    }
    return 0;
}

static AggregateFilter parse_aggregate_filter(Clingo::Symbol const &filter_symbol) {
    if (!is_named_function(filter_symbol, "__filter")) {
        throw std::runtime_error("Sintassi euristica malformata: filtro aggregato non valido; usa __filter(source_idx, target_idx, offset?).");
    }

    auto const args = filter_symbol.arguments();
    if (args.size() < 2 || args.size() > 3 ||
        !is_clingo_symbol_number(args[0]) ||
        !is_clingo_symbol_number(args[1]) ||
        (args.size() == 3 && !is_clingo_symbol_number(args[2]))) {
        throw std::runtime_error("Sintassi euristica malformata: __filter richiede indici numerici e offset numerico opzionale.");
    }

    AggregateFilter filter;
    filter.source_arg_index = args[0].number();
    filter.target_arg_index = args[1].number();
    filter.target_offset = args.size() == 3 ? args[2].number() : 0;
    if (filter.source_arg_index < 0 || filter.target_arg_index < 0) {
        throw std::runtime_error("Sintassi euristica malformata: gli indici di __filter devono essere non negativi.");
    }
    return filter;
}

static BodyMatch parse_body_match(Clingo::Symbol const &match_symbol) {
    if (!is_named_function(match_symbol, "__match")) {
        throw std::runtime_error("Sintassi euristica malformata: mapping body non valido; usa __match(source_idx, target_idx).");
    }

    auto const args = match_symbol.arguments();
    if (args.size() != 2 ||
        !is_clingo_symbol_number(args[0]) ||
        !is_clingo_symbol_number(args[1])) {
        throw std::runtime_error("Sintassi euristica malformata: __match richiede due indici numerici.");
    }

    BodyMatch match;
    match.source_arg_index = args[0].number();
    match.target_arg_index = args[1].number();
    if (match.source_arg_index < 0 || match.target_arg_index < 0) {
        throw std::runtime_error("Sintassi euristica malformata: gli indici di __match devono essere non negativi.");
    }
    return match;
}

static BodyArgBinding parse_body_arg_binding(Clingo::Symbol const &binding_symbol) {
    if (!is_named_function(binding_symbol, "__bind_arg")) {
        throw std::runtime_error("Sintassi euristica malformata: binding body non valido; usa __bind_arg(var, source_idx).");
    }

    auto const args = binding_symbol.arguments();
    if (args.size() != 2 ||
        !is_nullary_function(args[0]) ||
        !is_clingo_symbol_number(args[1])) {
        throw std::runtime_error("Sintassi euristica malformata: __bind_arg richiede una variabile e un indice numerico.");
    }

    BodyArgBinding binding;
    binding.variable_name = args[0];
    binding.source_arg_index = args[1].number();
    if (binding.source_arg_index < 0) {
        throw std::runtime_error("Sintassi euristica malformata: l'indice di __bind_arg deve essere non negativo.");
    }
    return binding;
}

static BodyPredicateSpec parse_body_predicate_spec(Clingo::Symbol const &body_symbol) {
    if (!is_named_function(body_symbol, "__body")) {
        throw std::runtime_error("Sintassi euristica malformata: body esplicito non valido; usa __body(pred, ...).");
    }

    auto const args = body_symbol.arguments();
    if (args.empty() || !is_nullary_function(args[0])) {
        throw std::runtime_error("Sintassi euristica malformata: __body richiede __body(pred, ...).");
    }

    BodyPredicateSpec spec;
    spec.pred_name = args[0];
    spec.explicit_mapping = true;

    for (size_t i = 1; i < args.size(); ++i) {
        if (!is_clingo_symbol_function(args[i])) {
            throw std::runtime_error("Sintassi euristica malformata: argomento non valido in __body.");
        }
        std::string const nested_name = args[i].name();
        if (nested_name == "__match") {
            spec.matches.push_back(parse_body_match(args[i]));
        }
        else if (nested_name == "__bind_arg") {
            spec.arg_bindings.push_back(parse_body_arg_binding(args[i]));
        }
        else {
            throw std::runtime_error("Sintassi euristica malformata: argomento '" +
                                     nested_name + "' non valido in __body.");
        }
    }

    if (spec.matches.empty()) {
        throw std::runtime_error("Sintassi euristica malformata: __body richiede almeno un __match.");
    }

    return spec;
}

enum class AggregateOperator {
    Sum,
    Count,
    Min,
    Max,
    Unknown
};

static AggregateOperator parse_aggregate_op(std::string const &op_name) {
    if (op_name == "__sum") {
        return AggregateOperator::Sum;
    }
    if (op_name == "__count") {
        return AggregateOperator::Count;
    }
    if (op_name == "__min") {
        return AggregateOperator::Min;
    }
    if (op_name == "__max") {
        return AggregateOperator::Max;
    }
    return AggregateOperator::Unknown;
}

std::vector<HeuristicRuleTemplate> parse_lazy_heuristic_templates(std::vector<Clingo::Symbol> const &heuristic_symbols) {
    std::vector<HeuristicRuleTemplate> templates;
    templates.reserve(heuristic_symbols.size());

    for (auto const &symbol : heuristic_symbols) {
        auto const args = symbol.arguments();
        if (args.empty()) {
            throw std::runtime_error("Sintassi euristica malformata: __heuristic richiede argomenti.");
        }

        HeuristicRuleTemplate tmpl;
        tmpl.sign = HeuristicSign::True;
        bool has_target = false;
        bool has_weight = false;
        bool has_priority = false;
        bool has_sign = false;
        bool has_semantics = false;
        Clingo::Symbol weight_symbol = Clingo::Number(0);
        Clingo::Symbol priority_symbol = Clingo::Number(0);

        for (size_t i = 0; i < args.size(); ++i) {
            auto const &arg = args[i];
            if (!is_clingo_symbol_function(arg)) {
                throw std::runtime_error("Sintassi euristica malformata: argomento non valido in __heuristic");
            }

            std::string const arg_name = arg.name();
            auto const arg_args = arg.arguments();

            if (arg_name == "__target") {
                if (arg_args.size() != 1 || !is_nullary_function(arg_args[0])) {
                    throw std::runtime_error("Sintassi euristica malformata: __target richiede __target(pred).");
                }
                if (has_target) {
                    throw std::runtime_error("Sintassi euristica malformata: target duplicato in __heuristic.");
                }
                tmpl.target_pred = arg_args[0];
                has_target = true;
                continue;
            }

            if (arg_name == "__bind") {
                if (arg_args.size() != 2 || !is_nullary_function(arg_args[0]) || !is_clingo_symbol_function(arg_args[1])) {
                    throw std::runtime_error("Sintassi euristica malformata: __bind richiede __bind(var, __agg(pred, idx?, filters...)).");
                }

                Clingo::Symbol const var_symbol = arg_args[0];
                std::string const var_name = arg_args[0].name();
                if (tmpl.var_bindings.find(var_symbol) != tmpl.var_bindings.end() ||
                    tmpl.body_var_names.find(var_symbol) != tmpl.body_var_names.end()) {
                    throw std::runtime_error("Sintassi euristica malformata: variabile '" + var_name +
                                             "' definita piu' volte in __heuristic.");
                }

                std::string const agg_op_str = arg_args[1].name();
                auto const agg_inner = arg_args[1].arguments();
                AggregateOperator agg_op = parse_aggregate_op(agg_op_str);

                if (agg_op == AggregateOperator::Unknown || agg_inner.empty() ||
                    !is_nullary_function(agg_inner[0])) {
                    throw std::runtime_error("Sintassi euristica malformata: operatore aggregato sconosciuto o predicato interno mancante.");
                }

                Clingo::Symbol const pred_symbol = agg_inner[0];
                int arg_idx = -1;
                std::vector<AggregateFilter> filters;

                if (agg_inner.size() >= 2 && is_clingo_symbol_number(agg_inner[1])) {
                    arg_idx = agg_inner[1].number();
                    if (arg_idx < 0) {
                        throw std::runtime_error("Sintassi euristica malformata: indice aggregato negativo in __bind.");
                    }
                }
                else if (agg_inner.size() >= 2) {
                    throw std::runtime_error("Sintassi euristica malformata: indice aggregato non numerico in __bind.");
                }

                for (size_t j = 2; j < agg_inner.size(); ++j) {
                    filters.push_back(parse_aggregate_filter(agg_inner[j]));
                }

                AggregateKey key{Clingo::Id(agg_op_str.c_str()), pred_symbol, arg_idx, std::move(filters)};
                tmpl.var_bindings.emplace(var_symbol, std::move(key));
                continue;
            }

            if (arg_name == "__weight") {
                if (arg_args.size() != 1) {
                    throw std::runtime_error("Sintassi euristica malformata: __weight richiede esattamente un argomento.");
                }
                if (has_weight) {
                    throw std::runtime_error("Sintassi euristica malformata: __weight duplicato in __heuristic.");
                }
                has_weight = true;
                weight_symbol = arg_args[0];
                continue;
            }

            if (arg_name == "__priority") {
                if (arg_args.size() != 1) {
                    throw std::runtime_error("Sintassi euristica malformata: __priority richiede esattamente un argomento.");
                }
                if (has_priority) {
                    throw std::runtime_error("Sintassi euristica malformata: __priority duplicato in __heuristic.");
                }
                has_priority = true;
                priority_symbol = arg_args[0];
                continue;
            }

            if (arg_name == "__semantics") {
                if (arg_args.size() != 1 || !is_nullary_function(arg_args[0])) {
                    throw std::runtime_error("Sintassi euristica malformata: __semantics richiede __semantics(alpha|clingo).");
                }
                if (has_semantics) {
                    throw std::runtime_error("Sintassi euristica malformata: __semantics duplicato in __heuristic.");
                }
                HeuristicSemantics parsed_semantics;
                if (!try_parse_semantics(arg_args[0].name(), parsed_semantics)) {
                    throw std::runtime_error("Sintassi euristica malformata: semantica euristica sconosciuta.");
                }
                tmpl.semantics = parsed_semantics;
                has_semantics = true;
                continue;
            }

            if (arg_name == "__body") {
                BodyPredicateSpec spec = parse_body_predicate_spec(arg);
                for (auto const &binding : spec.arg_bindings) {
                    if (tmpl.var_bindings.find(binding.variable_name) != tmpl.var_bindings.end() ||
                        !tmpl.body_var_names.insert(binding.variable_name).second) {
                        throw std::runtime_error("Sintassi euristica malformata: variabile '" +
                                                 std::string(binding.variable_name.name()) +
                                                 "' definita piu' volte in __heuristic.");
                    }
                }
                tmpl.pos_body_preds.push_back(std::move(spec));
                continue;
            }

            if (arg_args.empty()) {
                HeuristicSign parsed_sign;

                if (try_parse_sign(arg_name, parsed_sign)) {
                    if (has_sign) {
                        throw std::runtime_error("Sintassi euristica malformata: modificatore di segno duplicato in __heuristic.");
                    }
                    tmpl.sign = parsed_sign;
                    has_sign = true;
                    continue;
                }

                if (arg_name == "self") {
                    if (has_weight) {
                        throw std::runtime_error("Sintassi euristica malformata: peso duplicato in __heuristic.");
                    }
                    has_weight = true;
                    weight_symbol = arg;
                    continue;
                }

                if (is_neg_body(arg_name)) {
                    std::string pred_name = strip_neg_prefix(arg_name);
                    tmpl.neg_body_preds.push_back(Clingo::Id(pred_name.c_str()));
                    continue;
                }

                BodyPredicateSpec spec;
                spec.pred_name = arg;
                tmpl.pos_body_preds.push_back(std::move(spec));
                continue;
            }

            throw std::runtime_error("Sintassi euristica malformata: argomento '" + arg_name +
                                     "' non riconosciuto in __heuristic.");
        }

        if (!has_target) {
            throw std::runtime_error("Sintassi euristica malformata: __heuristic richiede un argomento __target(pred).");
        }

        tmpl.weight_expr = parse_arithmetic_expression(weight_symbol, tmpl.var_bindings, tmpl.body_var_names, "__weight");
        tmpl.priority_expr = parse_arithmetic_expression(priority_symbol, tmpl.var_bindings, tmpl.body_var_names, "__priority");

        templates.push_back(std::move(tmpl));
    }

    return templates;
}
