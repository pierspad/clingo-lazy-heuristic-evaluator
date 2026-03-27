#include "clingo/heuristic_propagator.hh"
#include <iostream>

// ============================================================================
// init() — Punto di ingresso: decide quale modalità usare
// ============================================================================

void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    // Reset di tutte le strutture
    heuristic_targets_.clear();
    aggregate_states_.clear();
    watched_atoms_.clear();
    rule_templates_.clear();
    body_triggers_.clear();
    lazy_targets_.clear();
    active_body_lits_.clear();
    has_lazy_rules_ = false;

    auto atoms = init.symbolic_atoms();

    // Fase di rilevamento: cerchiamo prima __heuristic_rule/7
    // Se trovati, usiamo la modalità lazy; altrimenti fallback alla statica.
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        if (it->match("__heuristic_rule", 7)) {
            has_lazy_rules_ = true;
            break;
        }
    }

    if (has_lazy_rules_) {
        init_lazy_mode(init);
    } else {
        init_static_mode(init);
    }
}

// ============================================================================
// init_static_mode() — Modalità classica (backward-compatible)
// Legge __heuristic/4 da symbolic_atoms() (codice originale invariato)
// ============================================================================

void HeuristicPropagator::init_static_mode(Clingo::PropagateInit &init) {
    auto atoms = init.symbolic_atoms();

    std::unordered_map<std::string, std::vector<AggregateKey>> predicates_to_watch;

    // ---- PRIMA PASSATA: Estrazione delle direttive euristiche ----
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        if (it->match("__heuristic", 4)) {
            auto args = it->symbol().arguments();

            // 1. Target
            auto target_it = atoms.find(args[0]);
            if (target_it == atoms.end()) continue;
            Clingo::literal_t target_lit = init.solver_literal(target_it->literal());
            if (target_lit == 0) continue;

            // 2. Weight (arg[1])
            int weight = args[1].type() == Clingo::SymbolType::Number ? args[1].number() : 0;

            // 2b. Literal dell'atomo __heuristic(...) stesso (per verifica condizione)
            Clingo::literal_t heuristic_lit = init.solver_literal(it->literal());

            // 3. Priority dinamica (arg[2], es. __sum(c), __count(c), __sum(c,1))
            AggregateKey agg_key{"", "", -1};

            if (args[2].type() == Clingo::SymbolType::Function) {
                std::string op_name = args[2].name();
                auto op_args = args[2].arguments();

                if (op_args.size() >= 1 && op_args[0].type() == Clingo::SymbolType::Function) {
                    std::string pred = op_args[0].name();
                    int arg_idx = -1;
                    if (op_args.size() >= 2 && op_args[1].type() == Clingo::SymbolType::Number) {
                        arg_idx = op_args[1].number();
                    }
                    agg_key = {op_name, pred, arg_idx};

                    if (aggregate_states_.find(agg_key) == aggregate_states_.end()) {
                        auto state = make_aggregate(op_name);
                        if (state) {
                            aggregate_states_[agg_key] = std::move(state);
                            predicates_to_watch[pred].push_back(agg_key);
                        }
                    } else {
                        auto &keys = predicates_to_watch[pred];
                        if (std::find(keys.begin(), keys.end(), agg_key) == keys.end()) {
                            keys.push_back(agg_key);
                        }
                    }
                }
            }

            heuristic_targets_.push_back({target_lit, heuristic_lit, weight, agg_key});
        }
    }

    // ---- SECONDA PASSATA: Registrazione dei watch sugli atomi aggregati ----
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        std::string pred_name = it->symbol().name();

        auto pred_it = predicates_to_watch.find(pred_name);
        if (pred_it == predicates_to_watch.end()) continue;

        auto args = it->symbol().arguments();

        for (auto const &agg_key : pred_it->second) {
            int value = 0;
            bool found = false;

            if (agg_key.arg_index >= 0) {
                int idx = agg_key.arg_index;
                if (idx < static_cast<int>(args.size()) &&
                    args[idx].type() == Clingo::SymbolType::Number) {
                    value = args[idx].number();
                    found = true;
                }
            } else {
                for (int i = static_cast<int>(args.size()) - 1; i >= 0; --i) {
                    if (args[i].type() == Clingo::SymbolType::Number) {
                        value = args[i].number();
                        found = true;
                        break;
                    }
                }
            }

            if (found) {
                Clingo::literal_t lit = init.solver_literal(it->literal());
                if (lit != 0) {
                    init.add_watch(lit);
                    auto watch_it = watched_atoms_.find(lit);
                    if (watch_it != watched_atoms_.end()) {
                        auto &keys = watch_it->second.keys;
                        if (std::find(keys.begin(), keys.end(), agg_key) == keys.end()) {
                            keys.push_back(agg_key);
                        }
                    } else {
                        watched_atoms_[lit] = {value, {agg_key}};
                    }
                }
            }
        }
    }
}

// ============================================================================
// init_lazy_mode() — Modalità lazy (ground-on-demand)
// Legge __heuristic_rule/7 come template, poi scansiona il dominio
// per pre-risolvere i literal e registrare i trigger.
// ============================================================================

void HeuristicPropagator::init_lazy_mode(Clingo::PropagateInit &init) {
    auto atoms = init.symbolic_atoms();

    // ---- FASE 1: Parsing dei template __heuristic_rule/7 ----
    //
    // Formato: __heuristic_rule(RuleID, TargetPred, BodyPred, NegBodyPred,
    //                           WeightSource, PrioritySpec, Sign)
    //
    // Esempio: __heuristic_rule(r1, b, x, c, self, __sum(c), true).

    // Set dei predicati body e dei predicati da aggregare per la scansione
    std::unordered_set<std::string> body_preds;
    std::unordered_set<std::string> target_preds;
    std::unordered_set<std::string> neg_body_preds;
    std::unordered_set<std::string> aggregate_preds;

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        if (!it->match("__heuristic_rule", 7)) continue;

        auto args = it->symbol().arguments();

        HeuristicRuleTemplate tmpl;

        // arg[0]: RuleID (funzione/costante simbolica)
        tmpl.rule_id = args[0].type() == Clingo::SymbolType::Function
                        ? args[0].name() : std::to_string(args[0].number());

        // arg[1]: TargetPred (funzione simbolica, es. "b")
        if (args[1].type() != Clingo::SymbolType::Function) continue;
        tmpl.target_pred = args[1].name();

        // arg[2]: BodyPred (funzione simbolica, es. "x")
        if (args[2].type() != Clingo::SymbolType::Function) continue;
        tmpl.body_pred = args[2].name();

        // arg[3]: NegBodyPred (funzione simbolica, es. "c")
        if (args[3].type() != Clingo::SymbolType::Function) continue;
        tmpl.neg_body_pred = args[3].name();

        // arg[4]: WeightSource ("self" o un numero)
        if (args[4].type() == Clingo::SymbolType::Function) {
            tmpl.weight_source = args[4].name();
        } else if (args[4].type() == Clingo::SymbolType::Number) {
            tmpl.weight_source = std::to_string(args[4].number());
        } else {
            tmpl.weight_source = "self";
        }

        // arg[5]: PrioritySpec (es. __sum(c))
        AggregateKey agg_key{"", "", -1};
        if (args[5].type() == Clingo::SymbolType::Function) {
            std::string op_name = args[5].name();
            auto op_args = args[5].arguments();
            if (op_args.size() >= 1 && op_args[0].type() == Clingo::SymbolType::Function) {
                std::string pred = op_args[0].name();
                int arg_idx = -1;
                if (op_args.size() >= 2 && op_args[1].type() == Clingo::SymbolType::Number) {
                    arg_idx = op_args[1].number();
                }
                agg_key = {op_name, pred, arg_idx};
                aggregate_preds.insert(pred);
            }
        }
        tmpl.agg_key = agg_key;

        // arg[6]: Sign ("true", "false", "sign")
        if (args[6].type() == Clingo::SymbolType::Function) {
            tmpl.sign = args[6].name();
        } else {
            tmpl.sign = "true";
        }

        // Registra i predicati da scansionare
        body_preds.insert(tmpl.body_pred);
        target_preds.insert(tmpl.target_pred);
        neg_body_preds.insert(tmpl.neg_body_pred);

        // Crea lo stato aggregato se non esiste
        if (!agg_key.op.empty() && aggregate_states_.find(agg_key) == aggregate_states_.end()) {
            auto state = make_aggregate(agg_key.op);
            if (state) {
                aggregate_states_[agg_key] = std::move(state);
            }
        }

        rule_templates_.push_back(std::move(tmpl));
    }

    if (rule_templates_.empty()) {
        has_lazy_rules_ = false;
        init_static_mode(init);
        return;
    }

    // ---- FASE 2: Scansione del dominio per costruire lookup tables ----
    //
    // Costruiamo mappe: predicato → { valore_intero → solver_literal }
    // Ci servono per risolvere i literal di target, neg_body e aggregati.

    // Mappa: pred_name → { valore_dominio → solver_literal }
    std::unordered_map<std::string, std::unordered_map<int, Clingo::literal_t>> pred_lit_map;

    // Tutti i predicati che dobbiamo risolvere
    std::unordered_set<std::string> all_preds;
    all_preds.insert(body_preds.begin(), body_preds.end());
    all_preds.insert(target_preds.begin(), target_preds.end());
    all_preds.insert(neg_body_preds.begin(), neg_body_preds.end());
    all_preds.insert(aggregate_preds.begin(), aggregate_preds.end());

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        std::string pname = it->symbol().name();
        if (all_preds.find(pname) == all_preds.end()) continue;

        auto sym_args = it->symbol().arguments();
        if (sym_args.size() == 0) continue;

        // Per predicati unari: il valore è il primo (e unico) argomento numerico
        int domain_val = 0;
        bool has_val = false;
        for (size_t i = 0; i < sym_args.size(); ++i) {
            if (sym_args[i].type() == Clingo::SymbolType::Number) {
                domain_val = sym_args[i].number();
                has_val = true;
                break;
            }
        }
        if (!has_val) continue;

        Clingo::literal_t slit = init.solver_literal(it->literal());
        if (slit != 0) {
            pred_lit_map[pname][domain_val] = slit;
        }
    }

    // ---- FASE 3: Pre-risolvere i trigger e registrare i watch ----
    //
    // Per ogni template × ogni valore nel dominio del body_pred,
    // risolviamo in anticipo i literal di target e neg_body,
    // e registriamo il watch sul body_literal.

    for (size_t ri = 0; ri < rule_templates_.size(); ++ri) {
        auto const &tmpl = rule_templates_[ri];

        auto body_it = pred_lit_map.find(tmpl.body_pred);
        if (body_it == pred_lit_map.end()) continue;

        auto target_map_it = pred_lit_map.find(tmpl.target_pred);
        auto neg_map_it = pred_lit_map.find(tmpl.neg_body_pred);

        for (auto const &[domain_val, body_lit] : body_it->second) {
            // Risolvi target_lit per questo valore di dominio
            Clingo::literal_t target_lit = 0;
            if (target_map_it != pred_lit_map.end()) {
                auto tit = target_map_it->second.find(domain_val);
                if (tit != target_map_it->second.end()) {
                    target_lit = tit->second;
                }
            }
            if (target_lit == 0) continue; // Target non esiste nel ground program

            // Risolvi neg_body_lit per questo valore di dominio
            Clingo::literal_t neg_body_lit = 0;
            if (neg_map_it != pred_lit_map.end()) {
                auto nit = neg_map_it->second.find(domain_val);
                if (nit != neg_map_it->second.end()) {
                    neg_body_lit = nit->second;
                }
            }

            // Calcola il peso
            int weight = 0;
            if (tmpl.weight_source == "self") {
                weight = domain_val;
            } else {
                try { weight = std::stoi(tmpl.weight_source); } catch (...) { weight = 0; }
            }

            // Registra il trigger
            BodyTriggerInfo trigger;
            trigger.rule_idx = ri;
            trigger.domain_value = domain_val;
            trigger.target_lit = target_lit;
            trigger.neg_body_lit = neg_body_lit;

            body_triggers_[body_lit].push_back(trigger);

            // Registra il watch sul body literal
            init.add_watch(body_lit);
        }
    }

    // ---- FASE 4: Registrazione watch sugli atomi aggregati ----
    //
    // Per gli aggregati, dobbiamo osservare i predicati come nella modalità
    // statica (es. c(X) per __sum(c)).

    for (auto const &tmpl : rule_templates_) {
        if (tmpl.agg_key.op.empty()) continue;

        auto agg_pred_it = pred_lit_map.find(tmpl.agg_key.pred);
        if (agg_pred_it == pred_lit_map.end()) continue;

        for (auto const &[domain_val, slit] : agg_pred_it->second) {
            init.add_watch(slit);

            auto watch_it = watched_atoms_.find(slit);
            if (watch_it != watched_atoms_.end()) {
                auto &keys = watch_it->second.keys;
                if (std::find(keys.begin(), keys.end(), tmpl.agg_key) == keys.end()) {
                    keys.push_back(tmpl.agg_key);
                }
            } else {
                watched_atoms_[slit] = {domain_val, {tmpl.agg_key}};
            }
        }
    }
}

// ============================================================================
// propagate() — Gestisce sia la modalità statica che lazy
// ============================================================================

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    static_cast<void>(control);

    for (auto lit : changes) {
        // --- Aggiornamento aggregati (comune a entrambe le modalità) ---
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            auto const &info = watch_it->second;
            for (auto const &key : info.keys) {
                auto state_it = aggregate_states_.find(key);
                if (state_it != aggregate_states_.end()) {
                    state_it->second->add(info.value);
                }
            }
        }

        // --- Modalità lazy: istanziazione dinamica dei target ---
        if (has_lazy_rules_) {
            auto trigger_it = body_triggers_.find(lit);
            if (trigger_it != body_triggers_.end()) {
                // Questo body literal è trigger per uno o più template.
                // Creiamo le istanze lazy corrispondenti.
                std::vector<LazyTargetInstance> instances;

                for (auto const &trigger : trigger_it->second) {
                    auto const &tmpl = rule_templates_[trigger.rule_idx];

                    LazyTargetInstance inst;
                    inst.target_lit = trigger.target_lit;
                    inst.neg_body_lit = trigger.neg_body_lit;
                    inst.weight = 0;

                    // Calcola il peso
                    if (tmpl.weight_source == "self") {
                        inst.weight = trigger.domain_value;
                    } else {
                        try { inst.weight = std::stoi(tmpl.weight_source); } catch (...) {}
                    }

                    inst.agg_key = tmpl.agg_key;
                    inst.rule_idx = trigger.rule_idx;

                    instances.push_back(inst);
                }

                if (!instances.empty()) {
                    lazy_targets_[lit] = std::move(instances);
                    active_body_lits_.push_back(lit);
                }
            }
        }
    }
}

// ============================================================================
// undo() — Annulla propagazioni durante il backtracking
// ============================================================================

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    static_cast<void>(control);

    for (auto lit : changes) {
        // --- Aggiornamento aggregati (comune) ---
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            auto const &info = watch_it->second;
            for (auto const &key : info.keys) {
                auto state_it = aggregate_states_.find(key);
                if (state_it != aggregate_states_.end()) {
                    state_it->second->remove(info.value);
                }
            }
        }

        // --- Modalità lazy: rimozione delle istanze create da questo literal ---
        if (has_lazy_rules_) {
            auto lazy_it = lazy_targets_.find(lit);
            if (lazy_it != lazy_targets_.end()) {
                lazy_targets_.erase(lazy_it);
                // Rimuovi da active_body_lits_
                auto abl_it = std::find(active_body_lits_.begin(),
                                        active_body_lits_.end(), lit);
                if (abl_it != active_body_lits_.end()) {
                    // Swap-and-pop per O(1)
                    *abl_it = active_body_lits_.back();
                    active_body_lits_.pop_back();
                }
            }
        }
    }
}

// ============================================================================
// decide() — Suggerisce il letterale da decidere
// ============================================================================

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id,
                                               Clingo::Assignment const &assignment,
                                               Clingo::literal_t fallback) {
    static_cast<void>(thread_id);
    static_cast<void>(fallback);

    Clingo::literal_t best_target = 0;
    int max_priority = -1;
    int best_weight = -1;

    if (has_lazy_rules_) {
        // ---- MODALITÀ LAZY ----
        // Iteriamo sulle istanze lazy create dinamicamente in propagate.
        // Solo le istanze il cui body literal è vero (presente in lazy_targets_)
        // vengono considerate.

        for (auto const &body_lit : active_body_lits_) {
            auto lazy_it = lazy_targets_.find(body_lit);
            if (lazy_it == lazy_targets_.end()) continue;

            for (auto const &inst : lazy_it->second) {
                // Verifica condizione negativa: neg_body_pred(X) NON deve essere vero
                if (inst.neg_body_lit != 0 &&
                    assignment.truth_value(inst.neg_body_lit) == Clingo::TruthValue::True) {
                    continue;
                }

                // Il target deve essere ancora libero (non assegnato)
                if (assignment.truth_value(inst.target_lit) != Clingo::TruthValue::Free) {
                    continue;
                }

                // Lettura O(1) del valore corrente dell'aggregato
                int current_priority = 0;
                if (!inst.agg_key.op.empty()) {
                    auto state_it = aggregate_states_.find(inst.agg_key);
                    if (state_it != aggregate_states_.end()) {
                        current_priority = state_it->second->result();
                    }
                }

                if (current_priority > max_priority ||
                   (current_priority == max_priority && inst.weight > best_weight)) {
                    max_priority = current_priority;
                    best_weight = inst.weight;
                    best_target = inst.target_lit;
                }
            }
        }
    } else {
        // ---- MODALITÀ STATICA (codice originale invariato) ----
        for (auto const &target_info : heuristic_targets_) {
            // Verifica che la condizione dell'euristica sia soddisfatta
            if (assignment.truth_value(target_info.heuristic_lit) != Clingo::TruthValue::True) {
                continue;
            }

            // Il target deve essere ancora libero
            if (assignment.truth_value(target_info.lit) != Clingo::TruthValue::Free) {
                continue;
            }

            // Lettura O(1) del valore corrente dell'aggregato
            int current_priority = 0;
            auto state_it = aggregate_states_.find(target_info.agg_key);
            if (state_it != aggregate_states_.end()) {
                current_priority = state_it->second->result();
            }

            if (current_priority > max_priority ||
               (current_priority == max_priority && target_info.weight > best_weight)) {
                max_priority = current_priority;
                best_weight = target_info.weight;
                best_target = target_info.lit;
            }
        }
    }

    return best_target;
}