#include "clingo/heuristic_propagator.hh"
#include <iostream>
#include <algorithm>

// ============================================================================
// Funzioni helper per il parsing flessibile degli argomenti __heuristic
// ============================================================================

/// Controlla se un nome di funzione è un aggregato per la priority (__sum, __count, __min, __max)
static bool is_aggregate_name(std::string const &name) {
    return name == "__sum" || name == "__count" || name == "__min" || name == "__max";
}

/// Controlla se un nome di funzione è un aggregato per il weight (__w_sum, __w_count, __w_min, __w_max)
static bool is_weight_aggregate_name(std::string const &name) {
    return name == "__w_sum" || name == "__w_count" || name == "__w_min" || name == "__w_max";
}

/// Converte il nome di un aggregato weight nel nome dell'operazione base
/// Es: "__w_sum" → "__sum", "__w_count" → "__count"
static std::string weight_agg_to_op(std::string const &name) {
    // "__w_sum" → "__" + "sum" = "__sum"
    return "__" + name.substr(4);
}

/// Controlla se un nome di funzione è un segno dell'euristica (true, false, sign)
static bool is_sign_name(std::string const &name) {
    return name == "true" || name == "false" || name == "sign";
}

/// Controlla se un nome di funzione inizia con il prefisso __n_ (body negativo)
static bool is_neg_body(std::string const &name) {
    return name.size() > 4 && name.substr(0, 4) == "__n_";
}

/// Estrae il nome del predicato rimuovendo il prefisso __n_
static std::string strip_neg_prefix(std::string const &name) {
    return name.substr(4);
}

// ============================================================================
// init() — Punto di ingresso: decide quale modalità usare
// ============================================================================
//
// Strategia di discriminazione tra static e lazy:
//   - Se troviamo un atomo __heuristic(...) il cui primo argomento è un
//     simbolo semplice senza argomenti (es. "b"), siamo in modalità lazy.
//   - Se il primo argomento è un atomo compound con argomenti (es. b(1)),
//     siamo in modalità statica (generato dal grounder di clingo).
//   - Se non troviamo nessun __heuristic, nessuna euristica viene attivata.
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

    // Fase di rilevamento: cerchiamo atomi con nome "__heuristic".
    // Se il primo argomento è un simbolo semplice (senza argomenti propri),
    // siamo in modalità lazy. Altrimenti, se è un atomo compound (es. b(1)),
    // siamo in modalità statica (generato da #heuristic di clingo).
    bool found_static = false;
    bool found_lazy = false;

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        std::string name = it->symbol().name();
        if (name != "__heuristic") continue;

        auto args = it->symbol().arguments();
        if (args.size() < 3) continue;

        // Il primo argomento determina la modalità:
        // - Se ha argomenti propri (es. b(1)) → statica
        // - Se è un simbolo semplice senza argomenti (es. b) → lazy
        if (args[0].type() == Clingo::SymbolType::Function) {
            auto first_arg_args = args[0].arguments();
            if (first_arg_args.size() > 0) {
                found_static = true;
            } else {
                found_lazy = true;
            }
        }

        if (found_static || found_lazy) break;
    }

    if (found_lazy) {
        has_lazy_rules_ = true;
        init_lazy_mode(init);
    } else if (found_static) {
        init_static_mode(init);
    }
    // Se nessun __heuristic trovato, nessuna euristica attiva
}

// ============================================================================
// init_static_mode() — Modalità classica (per regole __heuristic/4 custom)
// Legge __heuristic/4 da symbolic_atoms() (generati dalle regole custom
// non-ground, es. __heuristic(b(X),X,S,true) :- x(X), not c(X), S = __sum(c).
// NON sono generati da #heuristic di clingo!)
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
// Legge __heuristic/N come template con argomenti flessibili, poi scansiona
// il dominio per pre-risolvere i literal e registrare i trigger.
//
// Formato ASP: __heuristic(TargetPred, ...args...).
//
// Il primo argomento è sempre il predicato target.
// Gli argomenti successivi vengono classificati automaticamente:
//   - atomo semplice senza prefisso  → body positivo (es. x)
//   - prefisso __n_                  → body negativo (es. __n_c → c)
//   - "self"                         → weight = valore del dominio
//   - numero intero                  → weight costante
//   - __sum(p), __count(p), etc.     → aggregato per la priority
//   - "true" / "false" / "sign"      → segno dell'euristica
//
// Esempio: __heuristic(b, x, __n_c, self, __sum(c), true).
// ============================================================================

void HeuristicPropagator::init_lazy_mode(Clingo::PropagateInit &init) {
    auto atoms = init.symbolic_atoms();

    // ---- FASE 1: Parsing flessibile dei template __heuristic/N ----

    // Set dei predicati per la scansione del dominio
    std::unordered_set<std::string> body_preds;
    std::unordered_set<std::string> target_preds;
    std::unordered_set<std::string> neg_body_preds;
    std::unordered_set<std::string> aggregate_preds;

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        std::string sym_name = it->symbol().name();
        if (sym_name != "__heuristic") continue;

        auto args = it->symbol().arguments();
        if (args.size() < 3) continue; // Minimo: target, un body, un sign

        // Verifica che il primo argomento sia un simbolo semplice (lazy mode)
        if (args[0].type() != Clingo::SymbolType::Function) continue;
        if (args[0].arguments().size() > 0) continue; // Skip atomi compound (static mode)

        HeuristicRuleTemplate tmpl;

        // Primo argomento: sempre il target
        tmpl.target_pred = args[0].name();
        tmpl.weight_source = "";  // default: nessun weight specificato
        tmpl.sign = "true";       // default sign
        tmpl.priority_agg_key = {"", "", -1}; // default: nessun aggregato per la priority
        tmpl.weight_agg_key = {"", "", -1};    // default: nessun aggregato per il weight

        // Classificazione automatica degli argomenti successivi
        for (size_t i = 1; i < args.size(); ++i) {
            auto const &arg = args[i];

            if (arg.type() == Clingo::SymbolType::Number) {
                // Numero intero → weight costante
                tmpl.weight_source = std::to_string(arg.number());

            } else if (arg.type() == Clingo::SymbolType::Function) {
                std::string arg_name = arg.name();
                auto arg_args = arg.arguments();

                if (is_aggregate_name(arg_name) && arg_args.size() >= 1) {
                    // Aggregato per PRIORITY: __sum(c), __count(c), __min(c), __max(c)
                    if (arg_args[0].type() == Clingo::SymbolType::Function) {
                        std::string pred = arg_args[0].name();
                        int arg_idx = -1;
                        if (arg_args.size() >= 2 && arg_args[1].type() == Clingo::SymbolType::Number) {
                            arg_idx = arg_args[1].number();
                        }
                        tmpl.priority_agg_key = {arg_name, pred, arg_idx};
                        aggregate_preds.insert(pred);
                    }

                } else if (is_weight_aggregate_name(arg_name) && arg_args.size() >= 1) {
                    // Aggregato per WEIGHT: __w_sum(c), __w_count(c), __w_min(c), __w_max(c)
                    if (arg_args[0].type() == Clingo::SymbolType::Function) {
                        std::string pred = arg_args[0].name();
                        int arg_idx = -1;
                        if (arg_args.size() >= 2 && arg_args[1].type() == Clingo::SymbolType::Number) {
                            arg_idx = arg_args[1].number();
                        }
                        // Convertiamo "__w_sum" → "__sum" per usare lo stesso tipo di aggregato
                        std::string real_op = weight_agg_to_op(arg_name);
                        tmpl.weight_agg_key = {real_op, pred, arg_idx};
                        aggregate_preds.insert(pred);
                    }

                } else if (is_sign_name(arg_name) && arg_args.size() == 0) {
                    // Sign: true, false, sign
                    tmpl.sign = arg_name;

                } else if (arg_name == "self" && arg_args.size() == 0) {
                    // Weight source: self
                    tmpl.weight_source = "self";

                } else if (is_neg_body(arg_name) && arg_args.size() == 0) {
                    // Body negativo: __n_c → c
                    std::string real_pred = strip_neg_prefix(arg_name);
                    tmpl.neg_body_preds.push_back(real_pred);
                    neg_body_preds.insert(real_pred);

                } else if (arg_args.size() == 0) {
                    // Body positivo: atomo semplice senza prefisso speciale
                    tmpl.pos_body_preds.push_back(arg_name);
                    body_preds.insert(arg_name);
                }
                // Se ha argomenti ma non è un aggregato riconosciuto, lo ignoriamo
            }
        }

        // Se non è stato specificato un weight, default a 0
        if (tmpl.weight_source.empty()) {
            tmpl.weight_source = "0";
        }

        // Registra il predicato target
        target_preds.insert(tmpl.target_pred);

        // Crea lo stato aggregato per la priority se non esiste
        if (!tmpl.priority_agg_key.op.empty() && aggregate_states_.find(tmpl.priority_agg_key) == aggregate_states_.end()) {
            auto state = make_aggregate(tmpl.priority_agg_key.op);
            if (state) {
                aggregate_states_[tmpl.priority_agg_key] = std::move(state);
            }
        }

        // Crea lo stato aggregato per il weight se non esiste
        if (!tmpl.weight_agg_key.op.empty() && aggregate_states_.find(tmpl.weight_agg_key) == aggregate_states_.end()) {
            auto state = make_aggregate(tmpl.weight_agg_key.op);
            if (state) {
                aggregate_states_[tmpl.weight_agg_key] = std::move(state);
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

        // Per predicati unari: il valore è il primo argomento numerico
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
    // Per ogni template × ogni valore nel dominio del primo body_pred positivo,
    // risolviamo in anticipo i literal di target e neg_body,
    // e registriamo il watch sul body_literal.
    //
    // Con body positivi multipli, usiamo il primo come trigger principale.
    // Gli altri body positivi vengono verificati nel decide().

    for (size_t ri = 0; ri < rule_templates_.size(); ++ri) {
        auto const &tmpl = rule_templates_[ri];

        if (tmpl.pos_body_preds.empty()) continue;

        // Il primo body positivo è il trigger principale
        auto body_it = pred_lit_map.find(tmpl.pos_body_preds[0]);
        if (body_it == pred_lit_map.end()) continue;

        auto target_map_it = pred_lit_map.find(tmpl.target_pred);

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

            // Risolvi tutti i neg_body_lits per questo valore di dominio
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

            // Registra il trigger
            BodyTriggerInfo trigger;
            trigger.rule_idx = ri;
            trigger.domain_value = domain_val;
            trigger.target_lit = target_lit;
            trigger.neg_body_lits = std::move(neg_lits);

            body_triggers_[body_lit].push_back(std::move(trigger));

            // Registra il watch sul body literal
            init.add_watch(body_lit);
        }
    }

    // ---- FASE 4: Registrazione watch sugli atomi aggregati ----
    //
    // Per gli aggregati, dobbiamo osservare i predicati come nella modalità
    // statica (es. c(X) per __sum(c)).

    // Lambda helper per registrare i watch di un aggregato
    auto register_agg_watches = [&](AggregateKey const &agg_key) {
        if (agg_key.op.empty()) return;

        auto agg_pred_it = pred_lit_map.find(agg_key.pred);
        if (agg_pred_it == pred_lit_map.end()) return;

        for (auto const &[domain_val, slit] : agg_pred_it->second) {
            init.add_watch(slit);

            auto watch_it = watched_atoms_.find(slit);
            if (watch_it != watched_atoms_.end()) {
                auto &keys = watch_it->second.keys;
                if (std::find(keys.begin(), keys.end(), agg_key) == keys.end()) {
                    keys.push_back(agg_key);
                }
            } else {
                watched_atoms_[slit] = {domain_val, {agg_key}};
            }
        }
    };

    for (auto const &tmpl : rule_templates_) {
        register_agg_watches(tmpl.priority_agg_key);
        register_agg_watches(tmpl.weight_agg_key);
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
                    inst.neg_body_lits = trigger.neg_body_lits;
                    inst.weight = 0;

                    // Calcola il peso
                    if (tmpl.weight_source == "self") {
                        inst.weight = trigger.domain_value;
                    } else {
                        try { inst.weight = std::stoi(tmpl.weight_source); } catch (...) {}
                    }

                    inst.priority_agg_key = tmpl.priority_agg_key;
                    inst.weight_agg_key = tmpl.weight_agg_key;
                    inst.rule_idx = trigger.rule_idx;

                    instances.push_back(std::move(inst));
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
                // Verifica condizioni negative: NESSUN neg_body_pred(X) deve essere vero
                bool neg_satisfied = false;
                for (auto neg_lit : inst.neg_body_lits) {
                    if (neg_lit != 0 &&
                        assignment.truth_value(neg_lit) == Clingo::TruthValue::True) {
                        neg_satisfied = true;
                        break;
                    }
                }
                if (neg_satisfied) continue;

                // Il target deve essere ancora libero (non assegnato)
                if (assignment.truth_value(inst.target_lit) != Clingo::TruthValue::Free) {
                    continue;
                }

                // Lettura O(1) del valore corrente della priority
                int current_priority = 0;
                if (!inst.priority_agg_key.op.empty()) {
                    auto state_it = aggregate_states_.find(inst.priority_agg_key);
                    if (state_it != aggregate_states_.end()) {
                        current_priority = state_it->second->result();
                    }
                }

                // Lettura O(1) del valore corrente del weight
                int current_weight = inst.weight;
                if (!inst.weight_agg_key.op.empty()) {
                    auto w_state_it = aggregate_states_.find(inst.weight_agg_key);
                    if (w_state_it != aggregate_states_.end()) {
                        current_weight = w_state_it->second->result();
                    }
                }

                if (current_priority > max_priority ||
                   (current_priority == max_priority && current_weight > best_weight)) {
                    max_priority = current_priority;
                    best_weight = current_weight;
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