#include "clingo/heuristic_propagator.hh"
#include <algorithm>
#include <iostream>
#include <unordered_set>

static bool is_aggregate_name(std::string const &name) {
    return name == "__sum" || name == "__count" || name == "__min" || name == "__max";
}

static bool is_binop_name(std::string const &name) {
    return name == "__add" || name == "__sub" || name == "__mul";
}

static BinOp binop_from_name(std::string const &name) {
    if (name == "__add") return BinOp::ADD;
    if (name == "__sub") return BinOp::SUB;
    return BinOp::MUL; // __mul
}

static bool is_sign_name(std::string const &name) {
    return name == "true" || name == "false" || name == "sign";
}

static bool is_neg_body(std::string const &name) {
    return name.size() > 4 && name.compare(0, 4, "__n_") == 0;
}

static std::string strip_neg_prefix(std::string const &name) {
    return name.substr(4);
}

static bool extract_numeric_argument(Clingo::Symbol const &symbol, int arg_index, int &value) {
    if (symbol.type() != Clingo::SymbolType::Function) {
        return false;
    }

    auto const args = symbol.arguments();
    if (args.empty()) {
        return false;
    }

    if (arg_index >= 0) {
        int numeric_pos = 0;
        for (auto const &arg : args) {
            if (arg.type() != Clingo::SymbolType::Number) {
                continue;
            }
            if (numeric_pos == arg_index) {
                value = arg.number();
                return true;
            }
            ++numeric_pos;
        }
        return false;
    }

    bool found = false;
    for (auto const &arg : args) {
        if (arg.type() == Clingo::SymbolType::Number) {
            value = arg.number();
            found = true;
        }
    }
    return found;
}

static Clingo::literal_t apply_sign(std::string const &sign,
                                    Clingo::literal_t target_lit,
                                    Clingo::literal_t fallback) {
    if (sign == "false") {
        return -target_lit;
    }
    if (sign == "sign") {
        return fallback < 0 ? -target_lit : target_lit;
    }
    return target_lit;
}

std::unique_ptr<Expression> HeuristicPropagator::parse_expression(
    Clingo::Symbol const &sym,
    std::unordered_map<std::string, int> const &var_index_map,
    bool &ok,
    std::string &error_message)
{
    ok = true;
    error_message.clear();

    auto fail = [&](std::string message) {
        ok = false;
        error_message = std::move(message);
        return std::make_unique<ConstExpr>(0);
    };

    if (sym.type() == Clingo::SymbolType::Number) {
        return std::make_unique<ConstExpr>(sym.number());
    }

    if (sym.type() != Clingo::SymbolType::Function) {
        return fail("tipo simbolo non supportato in espressione");
    }

    std::string const name = sym.name();
    auto const args = sym.arguments();

    if (name == "self" && args.empty()) {
        return std::make_unique<SelfExpr>();
    }

    if (is_binop_name(name)) {
        if (args.size() != 2) {
            return fail("operatore " + name + " richiede arita' 2");
        }

        auto left = parse_expression(args[0], var_index_map, ok, error_message);
        if (!ok) {
            return std::make_unique<ConstExpr>(0);
        }

        auto right = parse_expression(args[1], var_index_map, ok, error_message);
        if (!ok) {
            return std::make_unique<ConstExpr>(0);
        }

        return std::make_unique<BinOpExpr>(binop_from_name(name), std::move(left), std::move(right));
    }

    if (args.empty()) {
        auto const it = var_index_map.find(name);
        if (it != var_index_map.end()) {
            return std::make_unique<VarExpr>(it->second);
        }
        return fail("simbolo '" + name + "' non dichiarato con __bind");
    }

    return fail("funzione non supportata in espressione: '" + name + "'");
}

void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    aggregate_states_.clear();
    watched_atoms_.clear();
    rule_templates_.clear();
    body_triggers_.clear();
    lazy_targets_.clear();
    active_body_lits_.clear();
    active_body_pos_.clear();
    env_buffer_.clear();

    auto atoms = init.symbolic_atoms();
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        if (it->symbol().name() == "__heuristic") {
            init_lazy_mode(init);
            return;
        }
    }
}

void HeuristicPropagator::parse_lazy_templates(Clingo::SymbolicAtoms const &atoms, LazyInitInfo &info) {
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        parse_lazy_template_symbol(it->symbol(), info);
    }
}

void HeuristicPropagator::parse_lazy_template_symbol(Clingo::Symbol const &symbol, LazyInitInfo &info) {
    if (symbol.type() != Clingo::SymbolType::Function || symbol.name() != "__heuristic") {
        return;
    }

    auto const args = symbol.arguments();
    if (args.size() < 3) {
        return;
    }

    if (args[0].type() != Clingo::SymbolType::Function || !args[0].arguments().empty()) {
        return;
    }

    HeuristicRuleTemplate tmpl;
    tmpl.target_pred = args[0].name();
    tmpl.sign = "true";

    TemplateParseState state;
    for (size_t i = 1; i < args.size(); ++i) {
        parse_template_argument(args[i], tmpl, info, state);
    }

    finalize_lazy_template(tmpl, info, state);
}

void HeuristicPropagator::parse_template_argument(Clingo::Symbol const &arg,
                                                  HeuristicRuleTemplate &tmpl,
                                                  LazyInitInfo &info,
                                                  TemplateParseState &state) {
    if (arg.type() == Clingo::SymbolType::Number) {
        if (!state.weight_term && !state.legacy_weight_expr) {
            state.legacy_weight_expr = std::make_unique<ConstExpr>(arg.number());
        }
        return;
    }

    if (arg.type() != Clingo::SymbolType::Function) {
        return;
    }

    std::string const arg_name = arg.name();
    auto const arg_args = arg.arguments();

    if (arg_name == "__bind") {
        if (arg_args.size() != 2 ||
            arg_args[0].type() != Clingo::SymbolType::Function ||
            !arg_args[0].arguments().empty() ||
            arg_args[1].type() != Clingo::SymbolType::Function) {
            std::cerr << "[heuristic_propagator] __bind malformato in __heuristic("
                      << tmpl.target_pred << ", ...): atteso __bind(var, __agg(pred[, idx])).\n";
            return;
        }

        std::string const var_name = arg_args[0].name();
        std::string const agg_op = arg_args[1].name();
        auto const agg_inner_args = arg_args[1].arguments();

        if (!is_aggregate_name(agg_op) ||
            agg_inner_args.empty() ||
            agg_inner_args[0].type() != Clingo::SymbolType::Function) {
            std::cerr << "[heuristic_propagator] aggregato non valido in __bind("
                      << var_name << ", ...): supportati __sum/__count/__min/__max.\n";
            return;
        }

        if (state.var_index_map.find(var_name) != state.var_index_map.end()) {
            std::cerr << "[heuristic_propagator] variabile duplicata in __bind: '"
                      << var_name << "'.\n";
            return;
        }

        std::string const pred = agg_inner_args[0].name();
        int arg_idx = -1;
        if (agg_inner_args.size() >= 2 &&
            agg_inner_args[1].type() == Clingo::SymbolType::Number) {
            arg_idx = agg_inner_args[1].number();
        }

        AggregateKey key{agg_op, pred, arg_idx};
        VarBinding binding;
        binding.env_index = state.next_var_index++;
        binding.agg_key = key;

        state.var_index_map[var_name] = binding.env_index;
        tmpl.var_bindings.push_back(binding);
        info.aggregate_preds.insert(pred);
        return;
    }

    if (arg_name == "__weight") {
        if (arg_args.size() != 1) {
            std::cerr << "[heuristic_propagator] __weight malformato in __heuristic("
                      << tmpl.target_pred << ", ...): atteso __weight(expr).\n";
            return;
        }
        if (state.weight_term) {
            std::cerr << "[heuristic_propagator] __weight duplicato in __heuristic("
                      << tmpl.target_pred << ", ...): uso l'ultimo valore.\n";
        }
        state.weight_term = std::make_unique<Clingo::Symbol>(arg_args[0]);
        return;
    }

    if (arg_name == "__priority") {
        if (arg_args.size() != 1) {
            std::cerr << "[heuristic_propagator] __priority malformato in __heuristic("
                      << tmpl.target_pred << ", ...): atteso __priority(expr).\n";
            return;
        }
        if (state.priority_term) {
            std::cerr << "[heuristic_propagator] __priority duplicato in __heuristic("
                      << tmpl.target_pred << ", ...): uso l'ultimo valore.\n";
        }
        state.priority_term = std::make_unique<Clingo::Symbol>(arg_args[0]);
        return;
    }

    if (is_sign_name(arg_name) && arg_args.empty()) {
        tmpl.sign = arg_name;
        return;
    }

    if (arg_name == "self" && arg_args.empty()) {
        if (!state.weight_term && !state.legacy_weight_expr) {
            state.legacy_weight_expr = std::make_unique<SelfExpr>();
        }
        return;
    }

    if (is_neg_body(arg_name) && arg_args.empty()) {
        std::string const real_pred = strip_neg_prefix(arg_name);
        tmpl.neg_body_preds.push_back(real_pred);
        info.neg_body_preds.insert(real_pred);
        return;
    }

    if (arg_args.empty() && !is_aggregate_name(arg_name)) {
        tmpl.pos_body_preds.push_back(arg_name);
        info.body_preds.insert(arg_name);
    }
}

void HeuristicPropagator::finalize_lazy_template(HeuristicRuleTemplate &tmpl,
                                                 LazyInitInfo &info,
                                                 TemplateParseState &state) {
    tmpl.env_size = state.next_var_index;
    info.max_env_size = std::max(info.max_env_size, tmpl.env_size);

    if (state.weight_term) {
        bool ok = true;
        std::string error_message;
        auto expr = parse_expression(*state.weight_term, state.var_index_map, ok, error_message);
        if (ok) {
            tmpl.weight_expr = std::move(expr);
        }
        else {
            std::cerr << "[heuristic_propagator] errore parsing __weight in __heuristic("
                      << tmpl.target_pred << ", ...): " << error_message
                      << ". Uso fallback 0.\n";
            tmpl.weight_expr = std::make_unique<ConstExpr>(0);
        }
    }

    if (!state.weight_term && state.legacy_weight_expr) {
        tmpl.weight_expr = std::move(state.legacy_weight_expr);
    }

    if (state.priority_term) {
        bool ok = true;
        std::string error_message;
        auto expr = parse_expression(*state.priority_term, state.var_index_map, ok, error_message);
        if (ok) {
            tmpl.priority_expr = std::move(expr);
        }
        else {
            std::cerr << "[heuristic_propagator] errore parsing __priority in __heuristic("
                      << tmpl.target_pred << ", ...): " << error_message
                      << ". Uso fallback 0.\n";
            tmpl.priority_expr = std::make_unique<ConstExpr>(0);
        }
    }

    tmpl.weight_depends_on_bindings = tmpl.weight_expr->depends_on_bindings();
    tmpl.priority_depends_on_bindings = tmpl.priority_expr->depends_on_bindings();

    info.target_preds.insert(tmpl.target_pred);

    for (auto const &vb : tmpl.var_bindings) {
        if (aggregate_states_.find(vb.agg_key) != aggregate_states_.end()) {
            continue;
        }
        if (auto state_obj = make_aggregate(vb.agg_key.op)) {
            aggregate_states_.emplace(vb.agg_key, std::move(state_obj));
        }
    }

    rule_templates_.push_back(std::move(tmpl));
}

HeuristicPropagator::PredLitMap HeuristicPropagator::build_pred_lit_map(Clingo::PropagateInit &init,
                                                                         Clingo::SymbolicAtoms const &atoms,
                                                                         LazyInitInfo const &info) {
    PredLitMap pred_lit_map;
    std::unordered_set<std::string> all_preds;
    all_preds.insert(info.body_preds.begin(), info.body_preds.end());
    all_preds.insert(info.target_preds.begin(), info.target_preds.end());
    all_preds.insert(info.neg_body_preds.begin(), info.neg_body_preds.end());
    all_preds.insert(info.aggregate_preds.begin(), info.aggregate_preds.end());

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const pname = it->symbol().name();
        if (all_preds.find(pname) == all_preds.end()) continue;

        auto const sym_args = it->symbol().arguments();
        if (sym_args.empty()) continue;

        int domain_val = 0;
        if (!extract_numeric_argument(it->symbol(), 0, domain_val)) {
            continue;
        }

        Clingo::literal_t slit = init.solver_literal(it->literal());
        if (slit != 0) {
            pred_lit_map[pname][domain_val] = slit;
        }
    }

    return pred_lit_map;
}

void HeuristicPropagator::build_body_triggers(Clingo::PropagateInit &init, PredLitMap const &pred_lit_map) {
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
                if (tit != target_map_it->second.end()) {
                    target_lit = tit->second;
                }
            }
            if (target_lit == 0) continue;

            std::vector<Clingo::literal_t> neg_lits;
            for (auto const &neg_pred : tmpl.neg_body_preds) {
                auto neg_map_it = pred_lit_map.find(neg_pred);
                if (neg_map_it != pred_lit_map.end()) {
                    auto nit = neg_map_it->second.find(domain_val);
                    if (nit != neg_map_it->second.end()) {
                        neg_lits.push_back(nit->second);
                    }
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
}

void HeuristicPropagator::register_aggregate_watches(Clingo::PropagateInit &init,
                                                     Clingo::SymbolicAtoms const &atoms) {
    auto register_agg_watches = [&](AggregateKey const &agg_key) {
        if (agg_key.op.empty()) return;

        for (auto it = atoms.begin(); it != atoms.end(); ++it) {
            auto const symbol = it->symbol();
            if (symbol.name() != agg_key.pred) {
                continue;
            }

            int value = 0;
            if (!extract_numeric_argument(symbol, agg_key.arg_index, value)) {
                continue;
            }

            Clingo::literal_t const slit = init.solver_literal(it->literal());
            if (slit == 0) {
                continue;
            }

            init.add_watch(slit);

            auto &watch_info = watched_atoms_[slit];
            auto contrib_it = std::find_if(
                watch_info.contributions.begin(), watch_info.contributions.end(),
                [&](WatchedAtomContribution const &contrib) {
                    return contrib.key == agg_key;
                });
            if (contrib_it == watch_info.contributions.end()) {
                watch_info.contributions.push_back(WatchedAtomContribution{agg_key, value});
            }
        }
    };

    for (auto const &tmpl : rule_templates_) {
        for (auto const &vb : tmpl.var_bindings) {
            register_agg_watches(vb.agg_key);
        }
    }
}

void HeuristicPropagator::init_lazy_mode(Clingo::PropagateInit &init) {
    auto atoms = init.symbolic_atoms();
    LazyInitInfo info;

    parse_lazy_templates(atoms, info);
    if (rule_templates_.empty()) {
        return;
    }

    env_buffer_.resize(info.max_env_size, 0);

    auto pred_lit_map = build_pred_lit_map(init, atoms, info);
    build_body_triggers(init, pred_lit_map);
    register_aggregate_watches(init, atoms);
}

void HeuristicPropagator::remove_active_body_lit(Clingo::literal_t body_lit) noexcept {
    auto pos_it = active_body_pos_.find(body_lit);
    if (pos_it == active_body_pos_.end()) {
        return;
    }

    size_t const pos = pos_it->second;
    size_t const last = active_body_lits_.size() - 1;
    Clingo::literal_t const last_lit = active_body_lits_[last];

    active_body_lits_[pos] = last_lit;
    active_body_lits_.pop_back();
    active_body_pos_.erase(pos_it);

    if (pos < active_body_lits_.size()) {
        active_body_pos_[last_lit] = pos;
    }
}

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    static_cast<void>(control);

    int *env = env_buffer_.data();

    for (auto lit : changes) {
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            auto const &info = watch_it->second;
            for (auto const &contrib : info.contributions) {
                auto state_it = aggregate_states_.find(contrib.key);
                if (state_it != aggregate_states_.end()) {
                    state_it->second->add(contrib.value);
                }
            }
        }

        auto trigger_it = body_triggers_.find(lit);
        if (trigger_it != body_triggers_.end()) {
            auto &target_vec = lazy_targets_[lit];
            target_vec.clear();
            target_vec.reserve(trigger_it->second.size());

            for (auto const &trigger : trigger_it->second) {
                auto const &tmpl = rule_templates_[trigger.rule_idx];

                LazyTargetInstance inst;
                inst.target_lit = trigger.target_lit;
                inst.neg_body_lits = trigger.neg_body_lits;
                inst.domain_value = trigger.domain_value;
                inst.rule_idx = trigger.rule_idx;

                env[ENV_SELF_INDEX] = inst.domain_value;
                if (!tmpl.weight_depends_on_bindings) {
                    inst.cached_weight = tmpl.weight_expr->evaluate(env);
                    inst.has_cached_weight = true;
                }
                if (!tmpl.priority_depends_on_bindings) {
                    inst.cached_priority = tmpl.priority_expr->evaluate(env);
                    inst.has_cached_priority = true;
                }

                target_vec.push_back(std::move(inst));
            }

            if (!target_vec.empty()) {
                if (active_body_pos_.find(lit) == active_body_pos_.end()) {
                    active_body_pos_[lit] = active_body_lits_.size();
                    active_body_lits_.push_back(lit);
                }
            } else {
                lazy_targets_.erase(lit);
                remove_active_body_lit(lit);
            }
        }
    }
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    static_cast<void>(control);

    for (auto lit : changes) {
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            auto const &info = watch_it->second;
            for (auto const &contrib : info.contributions) {
                auto state_it = aggregate_states_.find(contrib.key);
                if (state_it != aggregate_states_.end()) {
                    state_it->second->remove(contrib.value);
                }
            }
        }

        auto lazy_it = lazy_targets_.find(lit);
        if (lazy_it != lazy_targets_.end()) {
            lazy_targets_.erase(lazy_it);
            remove_active_body_lit(lit);
        }
    }
}

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id,
                                               Clingo::Assignment const &assignment,
                                               Clingo::literal_t fallback) {
    static_cast<void>(thread_id);

    Clingo::literal_t best_target = 0;
    std::string const *best_sign = nullptr;
    int max_priority = -1;
    int best_weight = -1;

    int *env = env_buffer_.data();

    for (auto const &body_lit : active_body_lits_) {
        auto lazy_it = lazy_targets_.find(body_lit);
        if (lazy_it == lazy_targets_.end()) continue;

        for (auto const &inst : lazy_it->second) {
            bool neg_satisfied = false;
            for (auto neg_lit : inst.neg_body_lits) {
                if (neg_lit != 0 &&
                    assignment.truth_value(neg_lit) == Clingo::TruthValue::True) {
                    neg_satisfied = true;
                    break;
                }
            }
            if (neg_satisfied) continue;

            if (assignment.truth_value(inst.target_lit) != Clingo::TruthValue::Free) {
                continue;
            }

            auto const &tmpl = rule_templates_[inst.rule_idx];

            bool need_weight_eval = !inst.has_cached_weight;
            bool need_priority_eval = !inst.has_cached_priority;

            if (need_weight_eval || need_priority_eval) {
                env[ENV_SELF_INDEX] = inst.domain_value;

                for (auto const &vb : tmpl.var_bindings) {
                    int val = 0;
                    auto state_it = aggregate_states_.find(vb.agg_key);
                    if (state_it != aggregate_states_.end()) {
                        val = state_it->second->result();
                    }
                    env[vb.env_index] = val;
                }
            }

            int current_priority = inst.has_cached_priority
                ? inst.cached_priority
                : tmpl.priority_expr->evaluate(env);
            int current_weight = inst.has_cached_weight
                ? inst.cached_weight
                : tmpl.weight_expr->evaluate(env);

            if (current_priority > max_priority ||
               (current_priority == max_priority && current_weight > best_weight)) {
                max_priority = current_priority;
                best_weight = current_weight;
                best_target = inst.target_lit;
                best_sign = &tmpl.sign;
            }
        }
    }

    if (best_target == 0 || best_sign == nullptr) {
        return 0;
    }
    return apply_sign(*best_sign, best_target, fallback);
}