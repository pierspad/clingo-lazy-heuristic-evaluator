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

static bool is_bound_variable(Clingo::Symbol const &symbol,
                              std::unordered_map<std::string, AggregateKey> const &bindings) {
    return is_nullary_function(symbol) && bindings.find(symbol.name()) != bindings.end();
}

static void validate_arithmetic_term(Clingo::Symbol const &term,
                                     std::unordered_map<std::string, AggregateKey> const &bindings,
                                     std::string const &field_name) {
    if (is_clingo_symbol_number(term)) return;

    if (!is_clingo_symbol_function(term)) {
        throw std::runtime_error("Sintassi euristica malformata: " + field_name +
                                 " accetta solo numeri, self, variabili __bind e __add/__sub/__mul.");
    }

    std::string const name = term.name();
    auto const args = term.arguments();

    if (args.empty()) {
        if (name == "self" || is_bound_variable(term, bindings)) return;
        throw std::runtime_error("Sintassi euristica malformata: variabile '" + name +
                                 "' usata in " + field_name + " ma non definita con __bind.");
    }

    if (parse_arithmetic_operator(name) == ArithmeticOperator::Unknown) {
        throw std::runtime_error("Sintassi euristica malformata: operatore '" + name +
                                 "' non valido in " + field_name + ".");
    }
    if (args.size() != 2) {
        throw std::runtime_error("Sintassi euristica malformata: operatore '" + name +
                                 "' in " + field_name + " richiede esattamente due argomenti.");
    }

    validate_arithmetic_term(args[0], bindings, field_name);
    validate_arithmetic_term(args[1], bindings, field_name);
}

static Clingo::literal_t apply_sign(HeuristicSign sign, Clingo::literal_t target_lit, Clingo::literal_t fallback) {
    switch (sign) {
        case HeuristicSign::True:  return target_lit;
        case HeuristicSign::False: return -target_lit;
        case HeuristicSign::FollowFallback: return fallback < 0 ? -target_lit : target_lit;
    }
    return target_lit;
}

static int evaluate_term(Clingo::Symbol const &term, int domain_value,
                         std::unordered_map<std::string, int> const &var_env) {
    if (is_clingo_symbol_number(term)) {
        return term.number();
    }
    if (!is_clingo_symbol_function(term)) {
        return 0;
    }

    std::string const name = term.name();
    auto const args = term.arguments();

    if (name == "self" && args.empty()) {
        return domain_value;
    }

    if (args.size() == 2) {
        int const lhs = evaluate_term(args[0], domain_value, var_env);
        int const rhs = evaluate_term(args[1], domain_value, var_env);
        switch (parse_arithmetic_operator(name)) {
            case ArithmeticOperator::Add: return lhs + rhs;
            case ArithmeticOperator::Sub: return lhs - rhs;
            case ArithmeticOperator::Mul: return lhs * rhs;
            case ArithmeticOperator::Unknown: break;
        }
    }

    if (args.empty()) {
        auto it = var_env.find(name);
        if (it != var_env.end()) return it->second;
    }

    return 0;
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
        tmpl.weight_term = Clingo::Number(0);
        tmpl.priority_term = Clingo::Number(0);

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

            // __bind(var, __agg(pred, idx?)) collega una variabile simbolica
            // a un aggregato mantenuto incrementalmente dal propagatore.
            if (arg_name == "__bind") {
                if (arg_args.size() != 2 || !is_nullary_function(arg_args[0]) || !is_clingo_symbol_function(arg_args[1])) {
                    throw std::runtime_error("Sintassi euristica malformata: __bind richiede __bind(var, __agg(pred, idx?)).");
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
                if (agg_inner.size() > 2) {
                    throw std::runtime_error("Sintassi euristica malformata: aggregato in __bind con troppi argomenti.");
                }

                std::string const pred = agg_inner[0].name();
                int arg_idx = -1;

                // Indice dell'argomento da aggregare, es. __sum(cost, 1).
                // Se manca resta -1 per compatibilita' con la vecchia forma.
                if (agg_inner.size() >= 2 && is_clingo_symbol_number(agg_inner[1]))
                    arg_idx = agg_inner[1].number();
                else if (agg_inner.size() >= 2) {
                    throw std::runtime_error("Sintassi euristica malformata: indice aggregato non numerico in __bind.");
                }

                AggregateKey key{agg_op_str, pred, arg_idx};
                tmpl.var_bindings[var_name] = key;
                all_agg_preds.insert(pred);

                if (aggregate_states_.find(key) == aggregate_states_.end()) {
                    if (auto state = make_aggregate(agg_op_str))
                        aggregate_states_.emplace(key, std::move(state));
                }
                continue;
            }

            // __weight(expr) viene salvato come termine Clingo e validato
            // dopo il ciclo, quando tutti i __bind sono gia' noti.
            if (arg_name == "__weight") {
                if (arg_args.size() != 1) {
                    throw std::runtime_error("Sintassi euristica malformata: __weight richiede esattamente un argomento.");
                }
                tmpl.weight_term = arg_args[0];
                continue;
            }

            // __priority(expr) segue le stesse regole di __weight(expr).
            if (arg_name == "__priority") {
                if (arg_args.size() != 1) {
                    throw std::runtime_error("Sintassi euristica malformata: __priority richiede esattamente un argomento.");
                }
                tmpl.priority_term = arg_args[0];
                continue;
            }

            if (arg_args.empty()) {
                HeuristicSign parsed_sign;
                if (try_parse_sign(arg_name, parsed_sign)) {
                    tmpl.sign = parsed_sign;
                    continue;
                }
                if (arg_name == "self") {
                    tmpl.weight_term = arg;
                    continue;
                }
                if (is_neg_body(arg_name)) {
                    std::string const real_pred = strip_neg_prefix(arg_name);
                    tmpl.neg_body_preds.push_back(real_pred);
                    all_neg_preds.insert(real_pred);
                    continue;
                }
                if (tmpl.pos_body_preds.empty()) {
                    tmpl.pos_body_preds.push_back(arg_name);
                    all_body_preds.insert(arg_name);
                }
                continue;
            }

            throw std::runtime_error("Sintassi euristica malformata: argomento '" + arg_name +
                                     "' non riconosciuto in __heuristic.");
        }

        validate_arithmetic_term(tmpl.weight_term, tmpl.var_bindings, "__weight");
        validate_arithmetic_term(tmpl.priority_term, tmpl.var_bindings, "__priority");

        all_target_preds.insert(tmpl.target_pred);
        rule_templates_.push_back(std::move(tmpl));
    }

    if (rule_templates_.empty()) return;

    // Phase 2: Build predicate -> (domain_value -> solver_literal) map
    using PredLitMap = std::unordered_map<std::string, std::unordered_map<int, Clingo::literal_t>>;
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

        int domain_val = 0;
        if (!extract_numeric_argument(symbol, 0, domain_val)) continue;

        Clingo::literal_t slit = init.solver_literal(it->literal());
        if (slit != 0) pred_lit_map[pname][domain_val] = slit;
    }

    // Phase 3: Build body triggers
    for (size_t ri = 0; ri < rule_templates_.size(); ++ri) {
        auto const &tmpl = rule_templates_[ri];
        if (tmpl.pos_body_preds.empty()) continue;

        auto body_it = pred_lit_map.find(tmpl.pos_body_preds[0]);
        if (body_it == pred_lit_map.end()) continue;

        auto target_map_it = pred_lit_map.find(tmpl.target_pred);

        for (auto const &entry : body_it->second) {
            int const domain_val = entry.first;
            Clingo::literal_t const body_lit = entry.second;

            Clingo::literal_t target_lit = 0;
            if (target_map_it != pred_lit_map.end()) {
                auto tit = target_map_it->second.find(domain_val);
                if (tit != target_map_it->second.end()) target_lit = tit->second;
            }
            if (target_lit == 0) continue;

            std::vector<Clingo::literal_t> neg_lits;
            for (auto const &neg_pred : tmpl.neg_body_preds) {
                auto neg_map_it = pred_lit_map.find(neg_pred);
                if (neg_map_it != pred_lit_map.end()) {
                    auto nit = neg_map_it->second.find(domain_val);
                    if (nit != neg_map_it->second.end()) neg_lits.push_back(nit->second);
                }
            }

            BodyTriggerInfo trigger;
            trigger.rule_idx = ri;
            trigger.domain_value = domain_val;
            trigger.target_lit = target_lit;
            trigger.neg_body_lits = std::move(neg_lits);

            body_triggers_[body_lit].push_back(std::move(trigger));
            init.add_watch(body_lit);
        }
    }

    // Phase 4: Register watches on aggregate source atoms
    for (auto const &tmpl : rule_templates_) {
        for (auto const &vb : tmpl.var_bindings) {
            AggregateKey const &agg_key = vb.second;

            for (auto it = atoms.begin(); it != atoms.end(); ++it) {
                auto const sym = it->symbol();
                if (!is_clingo_symbol_function(sym)) continue;
                if (sym.name() != agg_key.pred_name) continue;

                int value = 0;
                if (!extract_numeric_argument(sym, agg_key.arg_index, value)) continue;

                Clingo::literal_t const slit = init.solver_literal(it->literal());
                if (slit == 0) continue;

                init.add_watch(slit);

                auto &watch_info = watched_atoms_[slit];
                bool already = false;
                for (auto const &c : watch_info.contributions) {
                    if (c.key == agg_key) { already = true; break; }
                }
                if (!already)
                    watch_info.contributions.push_back(WatchedAtomContribution{agg_key, value});
            }
        }
    }
}

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    static_cast<void>(control);

    for (auto lit : changes) {
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            for (auto const &contrib : watch_it->second.contributions) {
                auto state_it = aggregate_states_.find(contrib.key);
                if (state_it != aggregate_states_.end())
                    state_it->second->add(contrib.value);
            }
        }

        auto trigger_it = body_triggers_.find(lit);
        if (trigger_it != body_triggers_.end()) {
            auto &target_vec = lazy_targets_[lit];
            target_vec.clear();

            for (size_t ti = 0; ti < trigger_it->second.size(); ++ti) {
                auto const &trigger = trigger_it->second[ti];
                target_vec.push_back({trigger.target_lit, trigger.domain_value, trigger.rule_idx, ti});
            }

            if (!target_vec.empty()) active_body_lits_.insert(lit);
            else active_body_lits_.erase(lit);
        }
    }
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    static_cast<void>(control);

    for (auto lit : changes) {
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            for (auto const &contrib : watch_it->second.contributions) {
                auto state_it = aggregate_states_.find(contrib.key);
                if (state_it != aggregate_states_.end())
                    state_it->second->remove(contrib.value);
            }
        }

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

    for (auto const &body_lit : active_body_lits_) {
        auto lazy_it = lazy_targets_.find(body_lit);
        if (lazy_it == lazy_targets_.end() || lazy_it->second.empty()) continue;

        auto trigger_it = body_triggers_.find(body_lit);

        for (auto const &inst : lazy_it->second) {
            bool neg_satisfied = false;
            if (trigger_it != body_triggers_.end() &&
                inst.trigger_index < trigger_it->second.size()) {
                auto const &trigger = trigger_it->second[inst.trigger_index];
                for (auto neg_lit : trigger.neg_body_lits) {
                    if (neg_lit != 0 &&
                        assignment.truth_value(neg_lit) == Clingo::TruthValue::True) {
                        neg_satisfied = true;
                        break;
                    }
                }
            }
            if (neg_satisfied) continue;

            if (assignment.truth_value(inst.target_lit) != Clingo::TruthValue::Free) continue;

            auto const &tmpl = rule_templates_[inst.rule_idx];

            std::unordered_map<std::string, int> var_env;
            for (auto const &vb : tmpl.var_bindings) {
                int val = 0;
                auto state_it = aggregate_states_.find(vb.second);
                if (state_it != aggregate_states_.end()) val = state_it->second->result();
                var_env[vb.first] = val;
            }

            int current_priority = evaluate_term(tmpl.priority_term, inst.domain_value, var_env);
            int current_weight = evaluate_term(tmpl.weight_term, inst.domain_value, var_env);

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
