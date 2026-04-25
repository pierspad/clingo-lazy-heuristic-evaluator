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
        throw std::runtime_error("Sintassi euristica malformata: variabile '" + name +
                                 "' usata in " + field_name + " ma non definita con __bind.");
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

    auto lhs = parse_arithmetic_expression(args[0], bindings, field_name);
    auto rhs = parse_arithmetic_expression(args[1], bindings, field_name);
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
    lazy_targets_.clear();
    active_body_lits_.clear();

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


void HeuristicPropagator::init_lazy_mode(Clingo::PropagateInit &init) {
    auto atoms = init.symbolic_atoms();

    std::unordered_set<std::string> all_body_preds;
    std::unordered_set<std::string> all_target_preds;
    std::unordered_set<std::string> all_neg_preds;
    std::unordered_set<std::string> all_agg_preds;

    // Phase 1: Parse __heuristic/N facts into rule templates.
    // In questa fase non registriamo ancora watch: costruiamo una descrizione
    // compatta delle euristiche e validiamo subito la sintassi strutturale.
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const symbol = it->symbol();

        if (!is_named_function(symbol, "__heuristic")) {
            continue;
        }

        // Il primo argomento e' il predicato target, gli altri descrivono corpo,
        // aggregati, peso, priorita' e segno.
        auto const args = symbol.arguments();
        if (args.size() < 2) {
            continue;
        }
        if (!is_nullary_function(args[0])) {
            continue;
        }

        // Il template conserva la forma generale della direttiva euristica;
        // le istanze concrete verranno create solo quando un body literal e'
        // assegnato a vero durante il solving.
        HeuristicRuleTemplate tmpl;
        tmpl.target_pred = args[0].name();
        tmpl.sign = HeuristicSign::True;
        Clingo::Symbol weight_symbol = Clingo::Number(0);
        Clingo::Symbol priority_symbol = Clingo::Number(0);

        // Classifica gli argomenti flessibili di __heuristic/N.
        for (size_t i = 1; i < args.size(); ++i) {
            auto const &arg = args[i];

            // Ogni argomento strutturale deve essere una funzione Clingo:
            // costanti come x/self/sign sono funzioni nullarie.
            if (!is_clingo_symbol_function(arg)) {
                throw std::runtime_error("Sintassi euristica malformata: argomento non valido in __heuristic");
            }

            std::string const arg_name = arg.name();
            auto const arg_args = arg.arguments();

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
                all_agg_preds.insert(pred);
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
                    all_neg_preds.insert(real_pred);
                    continue;
                }
                
                // 4. Registra tutti i body positivi. La fase trigger fara'
                //    l'intersezione sulla stessa tupla, quindi a(X), b(X)
                //    deve essere vero in entrambi i predicati.
                tmpl.pos_body_preds.push_back(arg_name);
                all_body_preds.insert(arg_name);
                continue;
            }

            // Se l'argomento ha arità > 0 ma non è stato gestito dai parser precedenti 
            // (es. non è __bind o __weight validi), solleva un errore di compilazione euristica.
            throw std::runtime_error("Sintassi euristica malformata: argomento '" + arg_name +
                                     "' non riconosciuto in __heuristic.");
        }

        // Da qui in poi peso/priorita' sono AST tipizzati, non piu' Symbol.
        tmpl.weight_expr = parse_arithmetic_expression(weight_symbol, tmpl.var_bindings, "__weight");
        tmpl.priority_expr = parse_arithmetic_expression(priority_symbol, tmpl.var_bindings, "__priority");

        all_target_preds.insert(tmpl.target_pred);
        rule_templates_.push_back(std::move(tmpl));
    }

    if (rule_templates_.empty()) return;

    // Phase 2: Build predicate -> (numeric tuple -> solver literal) map.
    // Prima era indicizzato solo dal primo argomento: b(X) andava bene, ma
    // assigned_sensor_unit(S,U) perdeva tutte le alternative con stesso S.
    using LitByTuple = std::unordered_map<AtomKey, Clingo::literal_t, AtomKeyHash>;
    using PredLitMap = std::unordered_map<std::string, LitByTuple>;
    PredLitMap pred_lit_map;

    std::unordered_set<std::string> all_preds;
    all_preds.insert(all_body_preds.begin(), all_body_preds.end());
    all_preds.insert(all_target_preds.begin(), all_target_preds.end());
    all_preds.insert(all_neg_preds.begin(), all_neg_preds.end());
    all_preds.insert(all_agg_preds.begin(), all_agg_preds.end());

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

    // Phase 3: Build body triggers.
    // Ogni trigger rappresenta una congiunzione di body positivi sulla stessa
    // tupla. Registriamo un watch su ciascun positivo: decide controllera'
    // comunque che tutti siano veri, quindi a(X), b(X) viene gestito davvero.
    std::unordered_set<Clingo::literal_t> watched_body_lits;
    for (size_t ri = 0; ri < rule_templates_.size(); ++ri) {
        auto const &tmpl = rule_templates_[ri];
        if (tmpl.pos_body_preds.empty()) continue;

        auto body_it = pred_lit_map.find(tmpl.pos_body_preds[0]);
        if (body_it == pred_lit_map.end()) continue;

        auto target_map_it = pred_lit_map.find(tmpl.target_pred);
        if (target_map_it == pred_lit_map.end()) continue;

        for (auto const &entry : body_it->second) {
            AtomKey const &tuple_key = entry.first;
            std::vector<Clingo::literal_t> pos_lits{entry.second};

            bool all_pos_available = true;
            for (size_t pi = 1; pi < tmpl.pos_body_preds.size(); ++pi) {
                auto pos_map_it = pred_lit_map.find(tmpl.pos_body_preds[pi]);
                if (pos_map_it == pred_lit_map.end()) {
                    all_pos_available = false;
                    break;
                }

                auto pit = pos_map_it->second.find(tuple_key);
                if (pit == pos_map_it->second.end()) {
                    all_pos_available = false;
                    break;
                }

                pos_lits.push_back(pit->second);
            }

            if (!all_pos_available) continue;

            Clingo::literal_t target_lit = 0;
            auto tit = target_map_it->second.find(tuple_key);
            if (tit != target_map_it->second.end()) target_lit = tit->second;
            if (target_lit == 0) continue;

            std::vector<Clingo::literal_t> neg_lits;
            for (auto const &neg_pred : tmpl.neg_body_preds) {
                auto neg_map_it = pred_lit_map.find(neg_pred);
                if (neg_map_it != pred_lit_map.end()) {
                    auto nit = neg_map_it->second.find(tuple_key);
                    if (nit != neg_map_it->second.end()) neg_lits.push_back(nit->second);
                }
            }

            BodyTriggerInfo trigger;
            trigger.rule_idx = ri;
            trigger.target_lit = target_lit;
            trigger.self_value = tuple_key.values.empty() ? 0 : tuple_key.values[0];
            trigger.tuple_values = tuple_key.values;
            trigger.pos_body_lits = pos_lits;
            trigger.neg_body_lits = std::move(neg_lits);

            for (auto body_lit : trigger.pos_body_lits) {
                body_triggers_[body_lit].push_back(trigger);
                if (watched_body_lits.insert(body_lit).second) {
                    init.add_watch(body_lit);
                }
            }
        }
    }

    // Phase 4: Register watches on aggregate source atoms.
    // Ogni atomo sorgente puo' contribuire a uno o piu' aggregati. Per gli
    // aggregati filtrati salviamo gia' la chiave runtime concreta, cosi'
    // propagate/undo fanno solo add/remove.
    std::unordered_set<Clingo::literal_t> watched_aggregate_lits;
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

                if (watched_aggregate_lits.insert(slit).second) {
                    init.add_watch(slit);
                }

                auto &watch_info = watched_atoms_[slit];
                bool already = false;
                for (auto const &c : watch_info.contributions) {
                    if (c.runtime_key == runtime_key && c.value == value) {
                        already = true;
                        break;
                    }
                }
                if (!already)
                    watch_info.contributions.push_back(WatchedAtomContribution{std::move(runtime_key), value});
            }
        }
    }
}

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    static_cast<void>(control);

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
            }
        }

        // 2. Se il literal e' un body positivo, prepara le istanze candidate.
        //    La congiunzione completa viene controllata in decide, dove abbiamo
        //    accesso all'assegnamento corrente.
        auto trigger_it = body_triggers_.find(lit);
        if (trigger_it != body_triggers_.end()) {
            auto &target_vec = lazy_targets_[lit];
            target_vec.clear();

            for (size_t ti = 0; ti < trigger_it->second.size(); ++ti) {
                auto const &trigger = trigger_it->second[ti];
                target_vec.push_back({
                    trigger.target_lit,
                    trigger.self_value,
                    trigger.tuple_values,
                    trigger.rule_idx,
                    ti
                });
            }

            if (!target_vec.empty()) active_body_lits_.insert(lit);
            else active_body_lits_.erase(lit);
        }
    }
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    static_cast<void>(control);

    for (auto lit : changes) {
        // 1. Ripristina gli aggregati quando clingo fa backtracking.
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            for (auto const &contrib : watch_it->second.contributions) {
                auto state_it = aggregate_states_.find(contrib.runtime_key);
                if (state_it != aggregate_states_.end())
                    state_it->second->remove(contrib.value);
            }
        }

        // 2. Il body positivo non e' piu' attivo a questo livello di search.
        auto lazy_it = lazy_targets_.find(lit);
        if (lazy_it != lazy_targets_.end() && !lazy_it->second.empty()) {
            lazy_it->second.clear();
            active_body_lits_.erase(lit);
        }
    }
}

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id,
                                               Clingo::Assignment const &assignment,
                                               Clingo::literal_t fallback) noexcept {
    static_cast<void>(thread_id);

    Clingo::literal_t best_target = 0;
    HeuristicSign best_sign = HeuristicSign::True;
    int max_priority = INT_MIN;
    int best_weight = INT_MIN;
    bool has_best = false;

    // Scorre solo i body che sono diventati veri durante la ricerca. Ogni
    // candidato viene rivalidato contro l'assegnamento corrente, cosi' i body
    // positivi multipli e i negativi restano semanticamente corretti.
    for (auto const &body_lit : active_body_lits_) {
        auto lazy_it = lazy_targets_.find(body_lit);
        if (lazy_it == lazy_targets_.end() || lazy_it->second.empty()) continue;

        auto trigger_it = body_triggers_.find(body_lit);

        for (auto const &inst : lazy_it->second) {
            bool pos_satisfied = true;
            bool neg_satisfied = false;
            if (trigger_it != body_triggers_.end() &&
                inst.trigger_index < trigger_it->second.size()) {
                auto const &trigger = trigger_it->second[inst.trigger_index];

                for (auto pos_lit : trigger.pos_body_lits) {
                    if (pos_lit == 0 ||
                        assignment.truth_value(pos_lit) != Clingo::TruthValue::True) {
                        pos_satisfied = false;
                        break;
                    }
                }

                for (auto neg_lit : trigger.neg_body_lits) {
                    if (neg_lit != 0 &&
                        assignment.truth_value(neg_lit) == Clingo::TruthValue::True) {
                        neg_satisfied = true;
                        break;
                    }
                }
            }
            if (!pos_satisfied || neg_satisfied) continue;

            if (assignment.truth_value(inst.target_lit) != Clingo::TruthValue::Free) continue;

            auto const &tmpl = rule_templates_[inst.rule_idx];

            // Costruisce l'ambiente delle variabili __bind per questa tupla.
            // Aggregati senza stato presente valgono 0, inclusi __min/__max vuoti.
            std::unordered_map<std::string, int> var_env;
            for (auto const &vb : tmpl.var_bindings) {
                int val = 0;
                RuntimeAggregateKey runtime_key;
                bool const valid_key = build_runtime_key_from_target_tuple(vb.second, inst.tuple_values, runtime_key);
                auto state_it = valid_key ? aggregate_states_.find(runtime_key) : aggregate_states_.end();
                if (state_it != aggregate_states_.end()) val = state_it->second->result();
                var_env[vb.first] = val;
            }

            int current_priority = evaluate_arithmetic_expression(tmpl.priority_expr, inst.self_value, var_env);
            int current_weight = evaluate_arithmetic_expression(tmpl.weight_expr, inst.self_value, var_env);

            // Clingo sceglie prima la priorita', poi il peso: manteniamo la
            // stessa logica per selezionare un unico literal suggerito.
            if (!has_best ||
                current_priority > max_priority ||
                (current_priority == max_priority && current_weight > best_weight)) {
                has_best = true;
                max_priority = current_priority;
                best_weight = current_weight;
                best_target = inst.target_lit;
                best_sign = tmpl.sign;
            }
        }
    }

    if (!has_best || best_target == 0) return 0;
    return apply_sign(best_sign, best_target, fallback);
}
