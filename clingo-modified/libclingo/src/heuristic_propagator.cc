#include "clingo/heuristic_propagator.hh"
#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <unordered_set>

static bool is_clingo_symbol_function(Clingo::Symbol const &symbol) {
    return symbol.type() == Clingo::SymbolType::Function;
}

static bool is_clingo_symbol_number(Clingo::Symbol const &symbol) {
    return symbol.type() == Clingo::SymbolType::Number;
}

static bool is_nullary_function(Clingo::Symbol const &symbol) {
    return is_clingo_symbol_function(symbol) && symbol.arguments().empty();
}

static bool is_named_function(Clingo::Symbol const &symbol, std::string const &name) {
    return is_clingo_symbol_function(symbol) && symbol.name() == name;
}

static bool try_parse_sign(std::string const &name, HeuristicSign &out) {
    if (name == "true")  { out = HeuristicSign::True; return true; }
    if (name == "false") { out = HeuristicSign::False; return true; }
    if (name == "sign")  { out = HeuristicSign::FollowFallback; return true; }
    return false;
}

static bool try_parse_semantics(std::string const &name, HeuristicSemantics &out) {
    if (name == "alpha")  { out = HeuristicSemantics::Alpha; return true; }
    if (name == "clingo") { out = HeuristicSemantics::Clingo; return true; }
    return false;
}

static bool is_neg_body(std::string const &name) {
    return name.size() > 4 && name.compare(0, 4, "__n_") == 0;
}

static std::string strip_neg_prefix(std::string const &name) {
    return name.substr(4);
}

static bool extract_numeric_arguments(Clingo::Symbol const &symbol, std::vector<int> &values) {
    if (!is_clingo_symbol_function(symbol)) return false;

    // Il propagatore MVP usa tuple numeriche come chiave di matching.
    // Questo copre BSP (X) e le euristiche PUP generate (S,U)/(Z,U).
    values.clear();
    for (auto const &arg : symbol.arguments()) {
        if (!is_clingo_symbol_number(arg)) return false;
        values.push_back(arg.number());
    }
    return !values.empty();
}

static bool extract_numeric_argument(Clingo::Symbol const &symbol, int arg_index, int &value) {
    if (!is_clingo_symbol_function(symbol)) return false;
    auto const args = symbol.arguments();
    if (args.empty()) return false;

    if (arg_index >= 0) {
        if (static_cast<size_t>(arg_index) >= args.size()) return false;
        if (!is_clingo_symbol_number(args[arg_index])) return false;
        value = args[arg_index].number();
        return true;
    }

    // Backward-compatible path for old __agg(pred) encodings: use the last
    // numeric argument when no positional index is available.
    bool found = false;
    for (auto const &arg : args) {
        if (is_clingo_symbol_number(arg)) { value = arg.number(); found = true; }
    }
    return found;
}

static bool extract_numeric_argument_from_args(Clingo::SymbolSpan const &args, int arg_index, int &value) {
    if (arg_index < 0 || static_cast<size_t>(arg_index) >= args.size()) return false;
    if (!is_clingo_symbol_number(args[arg_index])) return false;
    value = args[arg_index].number();
    return true;
}

enum class ArithmeticOperator {
    Add,
    Sub,
    Mul,
    Unknown
};

static ArithmeticOperator parse_arithmetic_operator(std::string const &name) {
    if (name == "__add") return ArithmeticOperator::Add;
    if (name == "__sub") return ArithmeticOperator::Sub;
    if (name == "__mul") return ArithmeticOperator::Mul;
    return ArithmeticOperator::Unknown;
}

static ArithmeticExpressionKind expression_kind_for_operator(ArithmeticOperator op) {
    switch (op) {
        case ArithmeticOperator::Add: return ArithmeticExpressionKind::Add;
        case ArithmeticOperator::Sub: return ArithmeticExpressionKind::Sub;
        case ArithmeticOperator::Mul: return ArithmeticExpressionKind::Mul;
        case ArithmeticOperator::Unknown: break;
    }
    return ArithmeticExpressionKind::Number;
}

static ArithmeticExpression parse_arithmetic_expression(
    Clingo::Symbol const &term,
    std::unordered_map<std::string, AggregateKey> const &bindings,
    std::unordered_set<std::string> const &body_vars,
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
    auto const args = term.arguments();

    // Costanti nullarie: self oppure una variabile definita con __bind.
    if (args.empty()) {
        if (name == "self") {
            return ArithmeticExpression::self();
        }
        if (bindings.find(name) != bindings.end()) {
            return ArithmeticExpression::bound_variable(name);
        }
        if (body_vars.find(name) != body_vars.end()) {
            return ArithmeticExpression::bound_variable(name);
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

static Clingo::literal_t apply_sign(HeuristicSign sign, Clingo::literal_t target_lit, Clingo::literal_t fallback) {
    switch (sign) {
        case HeuristicSign::True:  return target_lit;
        case HeuristicSign::False: return -target_lit;
        case HeuristicSign::FollowFallback: return fallback < 0 ? -target_lit : target_lit;
    }
    return target_lit;
}

static int evaluate_arithmetic_expression(
    ArithmeticExpression const &expr,
    int self_value,
    std::unordered_map<std::string, int> const &var_env
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
    binding.variable_name = args[0].name();
    binding.source_arg_index = args[1].number();
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
    spec.pred_name = args[0].name();
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

    return spec;
}

static bool body_matches_target(BodyPredicateSpec const &spec,
                                AtomKey const &body_key,
                                AtomKey const &target_key) {
    if (!spec.explicit_mapping) {
        return body_key == target_key;
    }

    for (auto const &match : spec.matches) {
        if (match.source_arg_index < 0 ||
            match.target_arg_index < 0 ||
            static_cast<size_t>(match.source_arg_index) >= body_key.values.size() ||
            static_cast<size_t>(match.target_arg_index) >= target_key.values.size()) {
            return false;
        }
        if (body_key.values[match.source_arg_index] != target_key.values[match.target_arg_index]) {
            return false;
        }
    }

    return !spec.matches.empty();
}

static bool collect_body_arg_values(BodyPredicateSpec const &spec,
                                    AtomKey const &body_key,
                                    std::unordered_map<std::string, int> &values) {
    for (auto const &binding : spec.arg_bindings) {
        if (binding.source_arg_index < 0 ||
            static_cast<size_t>(binding.source_arg_index) >= body_key.values.size()) {
            return false;
        }
        values[binding.variable_name] = body_key.values[binding.source_arg_index];
    }
    return true;
}

static bool build_runtime_key_from_source_atom(AggregateKey const &agg_key,
                                               Clingo::Symbol const &source_atom,
                                               RuntimeAggregateKey &runtime_key) {
    auto const args = source_atom.arguments();

    runtime_key.key = agg_key;
    runtime_key.filter_values.clear();
    runtime_key.filter_values.reserve(agg_key.filters.size());

    // Per ogni filtro salviamo il valore concreto dell'atomo sorgente.
    // In decide ricostruiremo la stessa chiave partendo dalla tupla target.
    for (auto const &filter : agg_key.filters) {
        int value = 0;
        if (!extract_numeric_argument_from_args(args, filter.source_arg_index, value)) {
            return false;
        }
        runtime_key.filter_values.push_back(value);
    }

    return true;
}

static bool build_runtime_key_from_target_tuple(AggregateKey const &agg_key,
                                                std::vector<int> const &tuple_values,
                                                RuntimeAggregateKey &runtime_key) {
    runtime_key.key = agg_key;
    runtime_key.filter_values.clear();
    runtime_key.filter_values.reserve(agg_key.filters.size());

    for (auto const &filter : agg_key.filters) {
        if (filter.target_arg_index < 0 ||
            static_cast<size_t>(filter.target_arg_index) >= tuple_values.size()) {
            return false;
        }
        runtime_key.filter_values.push_back(tuple_values[filter.target_arg_index] + filter.target_offset);
    }

    return true;
}

void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    aggregate_states_.clear();
    watched_atoms_.clear();
    rule_templates_.clear();
    body_triggers_.clear();
    candidates_.clear();
    candidate_queue_.clear();
    candidate_refresh_lits_.clear();
    aggregate_candidates_.clear();
    aggregate_source_lits_.clear();
    registered_watches_.clear();

    auto atoms = init.symbolic_atoms();
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        if (is_named_function(it->symbol(), "__heuristic")) {
            init_lazy_mode(init);
            return;
        }
    }
}

enum class AggregateOperator {
    Sum,
    Count,
    Min,
    Max,
    Unknown
};

static AggregateOperator parse_aggregate_op(std::string const &op_name) {
    if (op_name == "__sum") return AggregateOperator::Sum;
    if (op_name == "__count") return AggregateOperator::Count;
    if (op_name == "__min") return AggregateOperator::Min;
    if (op_name == "__max") return AggregateOperator::Max;
    return AggregateOperator::Unknown;
}


void HeuristicPropagator::parse_lazy_heuristic_templates(Clingo::SymbolicAtoms const &atoms) {
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const symbol = it->symbol();

        if (!is_named_function(symbol, "__heuristic")) {
            continue;
        }

        // Tutti gli argomenti sono strutturali e order-independent:
        // __target(pred), corpo, aggregati, peso, priorita' e segno.
        auto const args = symbol.arguments();
        if (args.empty()) {
            continue;
        }

        // Il template conserva la forma generale della direttiva euristica;
        // le istanze concrete verranno create solo quando un body literal e'
        // assegnato a vero durante il solving.
        HeuristicRuleTemplate tmpl;
        tmpl.sign = HeuristicSign::True;
        bool has_target = false;
        Clingo::Symbol weight_symbol = Clingo::Number(0);
        Clingo::Symbol priority_symbol = Clingo::Number(0);

        // Classifica gli argomenti flessibili di __heuristic/N.
        for (size_t i = 0; i < args.size(); ++i) {
            auto const &arg = args[i];

            // Ogni argomento strutturale deve essere una funzione Clingo:
            // costanti come x/self/sign sono funzioni nullarie.
            if (!is_clingo_symbol_function(arg)) {
                throw std::runtime_error("Sintassi euristica malformata: argomento non valido in __heuristic");
            }

            std::string const arg_name = arg.name();
            auto const arg_args = arg.arguments();

            // __target(pred) identifica esplicitamente il predicato target,
            // evitando dipendenze dall'ordine degli argomenti.
            if (arg_name == "__target") {
                if (arg_args.size() != 1 || !is_nullary_function(arg_args[0])) {
                    throw std::runtime_error("Sintassi euristica malformata: __target richiede __target(pred).");
                }
                if (has_target) {
                    throw std::runtime_error("Sintassi euristica malformata: target duplicato in __heuristic.");
                }
                tmpl.target_pred = arg_args[0].name();
                has_target = true;
                continue;
            }

            // __bind(var, __agg(pred, idx?, filters...)) collega una variabile
            // simbolica a un aggregato mantenuto incrementalmente.
            // Forme accettate:
            //   __bind(s, __sum(c, 0))
            //   __bind(n1, __max(num_sensors_on_unit, 0))
            //   __bind(k, __count(p, 1, __filter(0, 0)))
            if (arg_name == "__bind") {
                if (arg_args.size() != 2 || !is_nullary_function(arg_args[0]) || !is_clingo_symbol_function(arg_args[1])) {
                    throw std::runtime_error("Sintassi euristica malformata: __bind richiede __bind(var, __agg(pred, idx?, filters...)).");
                }

                std::string const var_name = arg_args[0].name();
                std::string const agg_op_str = arg_args[1].name();
                auto const agg_inner = arg_args[1].arguments();

                // L'operatore aggregato viene validato tramite enum, cosi' un
                // typo come __summ fallisce subito in init_lazy_mode.
                AggregateOperator agg_op = parse_aggregate_op(agg_op_str);

                if (agg_op == AggregateOperator::Unknown || agg_inner.empty() ||
                    !is_nullary_function(agg_inner[0])) {
                    throw std::runtime_error("Sintassi euristica malformata: operatore aggregato sconosciuto o predicato interno mancante.");
                }

                std::string const pred = agg_inner[0].name();
                int arg_idx = -1;
                std::vector<AggregateFilter> filters;

                // Indice dell'argomento da aggregare, es. __sum(cost, 1).
                // Se manca resta -1 per compatibilita' con la vecchia forma.
                if (agg_inner.size() >= 2 && is_clingo_symbol_number(agg_inner[1]))
                    arg_idx = agg_inner[1].number();
                else if (agg_inner.size() >= 2) {
                    throw std::runtime_error("Sintassi euristica malformata: indice aggregato non numerico in __bind.");
                }

                // I filtri sono opzionali e permettono aggregati contestuali:
                // es. __max(num_sensors_on_unit, 0, __filter(1, 1, -1)).
                for (size_t j = 2; j < agg_inner.size(); ++j) {
                    filters.push_back(parse_aggregate_filter(agg_inner[j]));
                }

                AggregateKey key{agg_op_str, pred, arg_idx, std::move(filters)};
                tmpl.var_bindings[var_name] = key;
                continue;
            }

            // __weight(expr) resta temporaneamente un Symbol locale: lo
            // trasformiamo in AST solo dopo aver visto tutti i __bind.
            if (arg_name == "__weight") {
                if (arg_args.size() != 1) {
                    throw std::runtime_error("Sintassi euristica malformata: __weight richiede esattamente un argomento.");
                }
                weight_symbol = arg_args[0];
                continue;
            }

            // __priority(expr) segue le stesse regole di __weight(expr).
            if (arg_name == "__priority") {
                if (arg_args.size() != 1) {
                    throw std::runtime_error("Sintassi euristica malformata: __priority richiede esattamente un argomento.");
                }
                priority_symbol = arg_args[0];
                continue;
            }

            // __semantics(clingo) richiede che i body negativi siano
            // assegnati esplicitamente a falso. Senza questo marcatore resta
            // la semantica alpha storica: basta che non siano veri.
            if (arg_name == "__semantics") {
                if (arg_args.size() != 1 || !is_nullary_function(arg_args[0])) {
                    throw std::runtime_error("Sintassi euristica malformata: __semantics richiede __semantics(alpha|clingo).");
                }
                HeuristicSemantics parsed_semantics;
                if (!try_parse_semantics(arg_args[0].name(), parsed_semantics)) {
                    throw std::runtime_error("Sintassi euristica malformata: semantica euristica sconosciuta.");
                }
                tmpl.semantics = parsed_semantics;
                continue;
            }

            // __body(pred, __match(...), __bind_arg(...)) permette di usare un
            // predicato ausiliario con una tupla diversa dal target, ad esempio
            // h_b(X,S) per pilotare b(X) e usare S in __priority(s).
            if (arg_name == "__body") {
                BodyPredicateSpec spec = parse_body_predicate_spec(arg);
                for (auto const &binding : spec.arg_bindings) {
                    tmpl.body_var_names.insert(binding.variable_name);
                }
                tmpl.pos_body_preds.push_back(std::move(spec));
                continue;
            }

            // Gestisce gli argomenti di arità zero (costanti o identificatori semplici)
            if (arg_args.empty()) {
                HeuristicSign parsed_sign;
                
                // 1. Determina la direzione dell'assegnamento euristico (es. true, false)
                if (try_parse_sign(arg_name, parsed_sign)) {
                    tmpl.sign = parsed_sign;
                    continue;
                }
                
                // 2. Shorthand: imposta direttamente il valore di dominio come peso
                if (arg_name == "self") {
                    weight_symbol = arg;
                    continue;
                }
                
                // 3. Registra eventuali predicati di body negativi necessari per l'attivazione
                if (is_neg_body(arg_name)) {
                    std::string const real_pred = strip_neg_prefix(arg_name);
                    tmpl.neg_body_preds.push_back(real_pred);
                    continue;
                }
                
                // 4. Registra tutti i body positivi. La fase trigger fara'
                //    l'intersezione sulla stessa tupla, quindi a(X), b(X)
                //    deve essere vero in entrambi i predicati.
                BodyPredicateSpec spec;
                spec.pred_name = arg_name;
                tmpl.pos_body_preds.push_back(std::move(spec));
                continue;
            }

            // Se l'argomento ha arità > 0 ma non è stato gestito dai parser precedenti 
            // (es. non è __bind o __weight validi), solleva un errore di compilazione euristica.
            throw std::runtime_error("Sintassi euristica malformata: argomento '" + arg_name +
                                     "' non riconosciuto in __heuristic.");
        }

        if (!has_target) {
            throw std::runtime_error("Sintassi euristica malformata: __heuristic richiede un argomento __target(pred).");
        }

        // Da qui in poi peso/priorita' sono AST tipizzati, non piu' Symbol.
        tmpl.weight_expr = parse_arithmetic_expression(weight_symbol, tmpl.var_bindings, tmpl.body_var_names, "__weight");
        tmpl.priority_expr = parse_arithmetic_expression(priority_symbol, tmpl.var_bindings, tmpl.body_var_names, "__priority");

        rule_templates_.push_back(std::move(tmpl));
    }
}

HeuristicPropagator::RulePredicateSets HeuristicPropagator::extract_lazy_predicate_sets() const {
    RulePredicateSets predicates;

    for (auto const &tmpl : rule_templates_) {
        predicates.target_preds.insert(tmpl.target_pred);

        for (auto const &pos_pred : tmpl.pos_body_preds) {
            predicates.body_preds.insert(pos_pred.pred_name);
        }

        for (auto const &neg_pred : tmpl.neg_body_preds) {
            predicates.neg_preds.insert(neg_pred);
        }

        for (auto const &binding : tmpl.var_bindings) {
            predicates.agg_preds.insert(binding.second.pred_name);
        }
    }

    return predicates;
}

HeuristicPropagator::PredLitMap HeuristicPropagator::build_lazy_predicate_literal_map(
    Clingo::PropagateInit &init,
    Clingo::SymbolicAtoms const &atoms,
    RulePredicateSets const &predicates
) const {
    PredLitMap pred_lit_map;

    std::unordered_set<std::string> all_preds;
    all_preds.insert(predicates.body_preds.begin(), predicates.body_preds.end());
    all_preds.insert(predicates.target_preds.begin(), predicates.target_preds.end());
    all_preds.insert(predicates.neg_preds.begin(), predicates.neg_preds.end());
    all_preds.insert(predicates.agg_preds.begin(), predicates.agg_preds.end());

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const symbol = it->symbol();
        if (!is_clingo_symbol_function(symbol)) continue;

        auto const pname = symbol.name();
        if (all_preds.find(pname) == all_preds.end()) continue;

        auto const sym_args = symbol.arguments();
        if (sym_args.empty()) continue;

        std::vector<int> tuple_values;
        if (!extract_numeric_arguments(symbol, tuple_values)) continue;

        Clingo::literal_t slit = init.solver_literal(it->literal());
        if (slit != 0) pred_lit_map[pname][AtomKey{std::move(tuple_values)}] = slit;
    }
    return pred_lit_map;
}

void HeuristicPropagator::add_solver_watch(Clingo::PropagateInit &init, Clingo::literal_t lit) {
    if (lit == 0) return;
    if (registered_watches_.insert(lit).second) {
        init.add_watch(lit);
    }
}

void HeuristicPropagator::register_candidate_refresh_watch(Clingo::PropagateInit &init,
                                                           Clingo::literal_t lit,
                                                           size_t candidate_id) {
    if (lit == 0) return;

    auto &ids = candidate_refresh_lits_[lit];
    if (std::find(ids.begin(), ids.end(), candidate_id) == ids.end()) {
        ids.push_back(candidate_id);
    }
    add_solver_watch(init, lit);
}

void HeuristicPropagator::erase_candidate_from_queue(size_t candidate_id) noexcept {
    if (candidate_id >= candidates_.size()) return;

    auto &candidate = candidates_[candidate_id];
    if (candidate.queued) {
        candidate_queue_.erase(candidate.queue_entry);
        candidate.queued = false;
    }
}

bool HeuristicPropagator::compute_candidate_entry(size_t candidate_id,
                                                  Clingo::Assignment const &assignment,
                                                  CandidateQueueEntry &entry) const {
    if (candidate_id >= candidates_.size()) return false;

    auto const &candidate = candidates_[candidate_id];
    auto const &tmpl = rule_templates_[candidate.rule_idx];

    if (candidate.target_lit == 0 ||
        assignment.truth_value(candidate.target_lit) != Clingo::TruthValue::Free) {
        return false;
    }

    for (auto pos_lit : candidate.pos_body_lits) {
        if (pos_lit == 0 ||
            assignment.truth_value(pos_lit) != Clingo::TruthValue::True) {
            return false;
        }
    }

    for (auto neg_lit : candidate.neg_body_lits) {
        if (neg_lit == 0) continue;
        auto const value = assignment.truth_value(neg_lit);
        if (tmpl.semantics == HeuristicSemantics::Clingo) {
            if (value != Clingo::TruthValue::False) return false;
        }
        else if (value == Clingo::TruthValue::True) {
            return false;
        }
    }

    std::unordered_map<std::string, int> var_env = candidate.body_var_values;
    for (auto const &binding : candidate.aggregate_bindings) {
        if (!binding.valid_key) {
            if (tmpl.semantics == HeuristicSemantics::Clingo) return false;
            var_env[binding.variable_name] = 0;
            continue;
        }

        if (tmpl.semantics == HeuristicSemantics::Clingo) {
            auto source_it = aggregate_source_lits_.find(binding.runtime_key);
            if (source_it != aggregate_source_lits_.end()) {
                for (auto source_lit : source_it->second) {
                    if (assignment.truth_value(source_lit) == Clingo::TruthValue::Free) {
                        return false;
                    }
                }
            }
        }

        int val = 0;
        auto state_it = aggregate_states_.find(binding.runtime_key);
        if (state_it != aggregate_states_.end() && state_it->second) {
            val = state_it->second->result();
        }
        var_env[binding.variable_name] = val;
    }

    entry.priority = evaluate_arithmetic_expression(tmpl.priority_expr, candidate.self_value, var_env);
    entry.weight = evaluate_arithmetic_expression(tmpl.weight_expr, candidate.self_value, var_env);
    entry.target_lit = candidate.target_lit;
    entry.candidate_id = candidate_id;
    return true;
}

void HeuristicPropagator::refresh_candidate(size_t candidate_id, Clingo::Assignment const &assignment) {
    if (candidate_id >= candidates_.size()) return;

    erase_candidate_from_queue(candidate_id);

    CandidateQueueEntry entry;
    if (compute_candidate_entry(candidate_id, assignment, entry)) {
        candidate_queue_.insert(entry);
        candidates_[candidate_id].queue_entry = entry;
        candidates_[candidate_id].queued = true;
    }
}

void HeuristicPropagator::refresh_candidate_noexcept(size_t candidate_id,
                                                     Clingo::Assignment const &assignment) noexcept {
    try {
        refresh_candidate(candidate_id, assignment);
    }
    catch (...) {
        erase_candidate_from_queue(candidate_id);
    }
}

void HeuristicPropagator::refresh_candidates_for_literal(Clingo::literal_t lit,
                                                         Clingo::Assignment const &assignment) {
    auto refresh_it = candidate_refresh_lits_.find(lit);
    if (refresh_it == candidate_refresh_lits_.end()) return;

    for (size_t candidate_id : refresh_it->second) {
        refresh_candidate(candidate_id, assignment);
    }
}

void HeuristicPropagator::refresh_candidates_for_literal_noexcept(Clingo::literal_t lit,
                                                                  Clingo::Assignment const &assignment) noexcept {
    auto refresh_it = candidate_refresh_lits_.find(lit);
    if (refresh_it == candidate_refresh_lits_.end()) return;

    for (size_t candidate_id : refresh_it->second) {
        refresh_candidate_noexcept(candidate_id, assignment);
    }
}

void HeuristicPropagator::refresh_candidates_for_aggregate(RuntimeAggregateKey const &runtime_key,
                                                           Clingo::Assignment const &assignment) {
    auto candidate_it = aggregate_candidates_.find(runtime_key);
    if (candidate_it == aggregate_candidates_.end()) return;

    for (size_t candidate_id : candidate_it->second) {
        refresh_candidate(candidate_id, assignment);
    }
}

void HeuristicPropagator::refresh_candidates_for_aggregate_noexcept(
    RuntimeAggregateKey const &runtime_key,
    Clingo::Assignment const &assignment
) noexcept {
    auto candidate_it = aggregate_candidates_.find(runtime_key);
    if (candidate_it == aggregate_candidates_.end()) return;

    for (size_t candidate_id : candidate_it->second) {
        refresh_candidate_noexcept(candidate_id, assignment);
    }
}

void HeuristicPropagator::refresh_all_candidates(Clingo::Assignment const &assignment) {
    for (size_t candidate_id = 0; candidate_id < candidates_.size(); ++candidate_id) {
        refresh_candidate(candidate_id, assignment);
    }
}

void HeuristicPropagator::register_lazy_body_triggers(Clingo::PropagateInit &init,
                                                      PredLitMap const &pred_lit_map) {
    for (size_t ri = 0; ri < rule_templates_.size(); ++ri) {
        auto const &tmpl = rule_templates_[ri];
        if (tmpl.pos_body_preds.empty()) continue;

        auto body_it = pred_lit_map.find(tmpl.pos_body_preds[0].pred_name);
        if (body_it == pred_lit_map.end()) continue;

        auto target_map_it = pred_lit_map.find(tmpl.target_pred);
        if (target_map_it == pred_lit_map.end()) continue;

        for (auto const &entry : body_it->second) {
            AtomKey const &body_key = entry.first;
            auto const &first_spec = tmpl.pos_body_preds[0];

            for (auto const &target_entry : target_map_it->second) {
                AtomKey const &target_key = target_entry.first;
                if (!body_matches_target(first_spec, body_key, target_key)) continue;

                std::vector<Clingo::literal_t> pos_lits{entry.second};
                std::unordered_map<std::string, int> body_var_values;
                if (!collect_body_arg_values(first_spec, body_key, body_var_values)) continue;

                bool all_pos_available = true;
                for (size_t pi = 1; pi < tmpl.pos_body_preds.size(); ++pi) {
                    auto const &spec = tmpl.pos_body_preds[pi];
                    auto pos_map_it = pred_lit_map.find(spec.pred_name);
                    if (pos_map_it == pred_lit_map.end()) {
                        all_pos_available = false;
                        break;
                    }

                    bool found_matching_body = false;
                    for (auto const &candidate : pos_map_it->second) {
                        if (!body_matches_target(spec, candidate.first, target_key)) continue;
                        std::unordered_map<std::string, int> candidate_values = body_var_values;
                        if (!collect_body_arg_values(spec, candidate.first, candidate_values)) continue;
                        body_var_values = std::move(candidate_values);
                        pos_lits.push_back(candidate.second);
                        found_matching_body = true;
                        break;
                    }

                    if (!found_matching_body) {
                        all_pos_available = false;
                        break;
                    }
                }

                if (!all_pos_available) continue;

                Clingo::literal_t target_lit = target_entry.second;
                if (target_lit == 0) continue;

                std::vector<Clingo::literal_t> neg_lits;
                for (auto const &neg_pred : tmpl.neg_body_preds) {
                    auto neg_map_it = pred_lit_map.find(neg_pred);
                    if (neg_map_it != pred_lit_map.end()) {
                        auto nit = neg_map_it->second.find(target_key);
                        if (nit != neg_map_it->second.end()) neg_lits.push_back(nit->second);
                    }
                }

                BodyTriggerInfo trigger;
                trigger.rule_idx = ri;
                trigger.candidate_id = candidates_.size();
                trigger.target_lit = target_lit;
                trigger.self_value = target_key.values.empty() ? 0 : target_key.values[0];
                trigger.tuple_values = target_key.values;
                trigger.body_var_values = std::move(body_var_values);
                trigger.pos_body_lits = pos_lits;
                trigger.neg_body_lits = std::move(neg_lits);

                CandidateState candidate;
                candidate.rule_idx = trigger.rule_idx;
                candidate.target_lit = trigger.target_lit;
                candidate.self_value = trigger.self_value;
                candidate.tuple_values = trigger.tuple_values;
                candidate.body_var_values = trigger.body_var_values;
                candidate.pos_body_lits = trigger.pos_body_lits;
                candidate.neg_body_lits = trigger.neg_body_lits;

                for (auto const &vb : tmpl.var_bindings) {
                    CandidateAggregateBinding aggregate_binding;
                    aggregate_binding.variable_name = vb.first;
                    aggregate_binding.valid_key = build_runtime_key_from_target_tuple(
                        vb.second,
                        candidate.tuple_values,
                        aggregate_binding.runtime_key
                    );
                    if (aggregate_binding.valid_key) {
                        auto &ids = aggregate_candidates_[aggregate_binding.runtime_key];
                        if (std::find(ids.begin(), ids.end(), trigger.candidate_id) == ids.end()) {
                            ids.push_back(trigger.candidate_id);
                        }
                    }
                    candidate.aggregate_bindings.push_back(std::move(aggregate_binding));
                }

                candidates_.push_back(std::move(candidate));

                register_candidate_refresh_watch(init, trigger.target_lit, trigger.candidate_id);
                register_candidate_refresh_watch(init, -trigger.target_lit, trigger.candidate_id);

                for (auto neg_lit : trigger.neg_body_lits) {
                    register_candidate_refresh_watch(init, neg_lit, trigger.candidate_id);
                    register_candidate_refresh_watch(init, -neg_lit, trigger.candidate_id);
                }

                for (auto body_lit : trigger.pos_body_lits) {
                    body_triggers_[body_lit].push_back(trigger);
                    register_candidate_refresh_watch(init, body_lit, trigger.candidate_id);
                }
            }
        }
    }
}

void HeuristicPropagator::register_lazy_aggregate_watches(Clingo::PropagateInit &init,
                                                          Clingo::SymbolicAtoms const &atoms) {
    auto assignment = init.assignment();

    for (auto const &tmpl : rule_templates_) {
        for (auto const &vb : tmpl.var_bindings) {
            AggregateKey const &agg_key = vb.second;

            for (auto it = atoms.begin(); it != atoms.end(); ++it) {
                auto const sym = it->symbol();
                if (!is_clingo_symbol_function(sym)) continue;
                if (sym.name() != agg_key.pred_name) continue;

                int value = 0;
                if (!extract_numeric_argument(sym, agg_key.arg_index, value)) continue;

                RuntimeAggregateKey runtime_key;
                if (!build_runtime_key_from_source_atom(agg_key, sym, runtime_key)) continue;

                Clingo::literal_t const slit = init.solver_literal(it->literal());
                if (slit == 0) continue;

                auto &source_lits = aggregate_source_lits_[runtime_key];
                if (std::find(source_lits.begin(), source_lits.end(), slit) == source_lits.end()) {
                    source_lits.push_back(slit);
                }

                add_solver_watch(init, slit);

                auto aggregate_candidate_it = aggregate_candidates_.find(runtime_key);
                if (aggregate_candidate_it != aggregate_candidates_.end()) {
                    for (size_t candidate_id : aggregate_candidate_it->second) {
                        register_candidate_refresh_watch(init, -slit, candidate_id);
                    }
                }

                auto &watch_info = watched_atoms_[slit];
                bool already = false;
                for (auto const &c : watch_info.contributions) {
                    if (c.runtime_key == runtime_key && c.value == value) {
                        already = true;
                        break;
                    }
                }
                if (!already) {
                    WatchedAtomContribution contribution{runtime_key, value};
                    auto &state = aggregate_states_[contribution.runtime_key];
                    if (!state) {
                        state = make_aggregate(contribution.runtime_key.key.op_name);
                    }
                    if (assignment.is_true(slit) && state) {
                        state->add(contribution.value);
                    }
                    watch_info.contributions.push_back(std::move(contribution));
                }
            }
        }
    }
}

void HeuristicPropagator::init_lazy_mode(Clingo::PropagateInit &init) {
    auto atoms = init.symbolic_atoms();

    // Phase 1: Parse __heuristic/N facts into rule templates.
    // In questa fase non registriamo ancora watch: costruiamo una descrizione
    // compatta delle euristiche e validiamo subito la sintassi strutturale.
    parse_lazy_heuristic_templates(atoms);
    if (rule_templates_.empty()) return;

    // Phase 2: Extract the predicate sets required by the runtime indexes.
    RulePredicateSets predicates = extract_lazy_predicate_sets();

    // Phase 3: Build predicate -> (numeric tuple -> solver literal) map.
    // Prima era indicizzato solo dal primo argomento: b(X) andava bene, ma
    // assigned_sensor_unit(S,U) perdeva tutte le alternative con stesso S.
    PredLitMap pred_lit_map = build_lazy_predicate_literal_map(init, atoms, predicates);

    // Phase 4: Build body triggers.
    // Ogni trigger rappresenta una congiunzione di body positivi sulla stessa
    // tupla. Registriamo un watch su ciascun positivo: decide controllera'
    // comunque che tutti siano veri, quindi a(X), b(X) viene gestito davvero.
    register_lazy_body_triggers(init, pred_lit_map);

    // Phase 5: Register watches on aggregate source atoms.
    // Ogni atomo sorgente puo' contribuire a uno o piu' aggregati. Per gli
    // aggregati filtrati salviamo gia' la chiave runtime concreta, cosi'
    // propagate/undo fanno solo add/remove.
    register_lazy_aggregate_watches(init, atoms);

    // Phase 6: Populate the decision queue for facts already true at level 0.
    // Da qui in poi decide consulta solo questa coda ordinata e rivalida il top.
    refresh_all_candidates(init.assignment());
}

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    auto assignment = control.assignment();

    for (auto lit : changes) {
        // 1. Aggiorna gli aggregati dinamici quando un atomo sorgente diventa vero.
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            for (auto const &contrib : watch_it->second.contributions) {
                auto &state = aggregate_states_[contrib.runtime_key];
                if (!state) {
                    state = make_aggregate(contrib.runtime_key.key.op_name);
                }
                if (state) {
                    state->add(contrib.value);
                }
                refresh_candidates_for_aggregate(contrib.runtime_key, assignment);
            }
        }

        // 2. Ogni literal osservato puo' abilitare/disabilitare un candidato:
        //    body positivo, target assegnato, negativo o sorgente aggregata falsa.
        refresh_candidates_for_literal(lit, assignment);
    }
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    auto assignment = control.assignment();

    for (auto lit : changes) {
        // 1. Ripristina gli aggregati quando clingo fa backtracking.
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            for (auto const &contrib : watch_it->second.contributions) {
                auto state_it = aggregate_states_.find(contrib.runtime_key);
                if (state_it != aggregate_states_.end())
                    state_it->second->remove(contrib.value);
                refresh_candidates_for_aggregate_noexcept(contrib.runtime_key, assignment);
            }
        }

        // 2. Backtracking su body/target/negativi/sorgenti false: rivalida i candidati.
        refresh_candidates_for_literal_noexcept(lit, assignment);
    }
}

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id,
                                               Clingo::Assignment const &assignment,
                                               Clingo::literal_t fallback) noexcept {
    static_cast<void>(thread_id);

    while (!candidate_queue_.empty()) {
        CandidateQueueEntry const entry = *candidate_queue_.begin();
        size_t const candidate_id = entry.candidate_id;

        if (candidate_id >= candidates_.size() ||
            !candidates_[candidate_id].queued ||
            !(candidates_[candidate_id].queue_entry == entry)) {
            candidate_queue_.erase(candidate_queue_.begin());
            continue;
        }

        CandidateQueueEntry refreshed;
        if (!compute_candidate_entry(candidate_id, assignment, refreshed)) {
            erase_candidate_from_queue(candidate_id);
            continue;
        }

        if (!(refreshed == entry)) {
            try {
                erase_candidate_from_queue(candidate_id);
                candidate_queue_.insert(refreshed);
                candidates_[candidate_id].queue_entry = refreshed;
                candidates_[candidate_id].queued = true;
            }
            catch (...) {
                erase_candidate_from_queue(candidate_id);
            }
            continue;
        }

        auto const &tmpl = rule_templates_[candidates_[candidate_id].rule_idx];
        return apply_sign(tmpl.sign, entry.target_lit, fallback);
    }

    return 0;
}
