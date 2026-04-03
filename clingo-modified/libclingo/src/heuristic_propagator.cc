#include "clingo/heuristic_propagator.hh"
#include <iostream>
#include <algorithm>

// ============================================================================
// Funzioni helper per il parsing flessibile degli argomenti __heuristic
// ============================================================================

/// Controlla se un nome di funzione è un aggregato (__sum, __count, __min, __max)
static bool is_aggregate_name(std::string const &name) {
    return name == "__sum" || name == "__count" || name == "__min" || name == "__max";
}

/// Controlla se un nome è un'operazione binaria (__add, __sub, __mul)
static bool is_binop_name(std::string const &name) {
    return name == "__add" || name == "__sub" || name == "__mul";
}

/// Converte il nome di un'operazione binaria nel tipo BinOp
static BinOp binop_from_name(std::string const &name) {
    if (name == "__add") return BinOp::ADD;
    if (name == "__sub") return BinOp::SUB;
    return BinOp::MUL; // __mul
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
// parse_expression() — Parsing ricorsivo di un termine Clingo in un AST
// ============================================================================
//
// Converte un Clingo::Symbol in un albero di Expression:
//   - Number(n)               → ConstExpr(n)
//   - self                    → SelfExpr()
//   - nome in known_vars      → VarExpr(nome)
//   - __add(a, b)             → BinOpExpr(ADD, parse(a), parse(b))
//   - __sub(a, b)             → BinOpExpr(SUB, parse(a), parse(b))
//   - __mul(a, b)             → BinOpExpr(MUL, parse(a), parse(b))
//
// Se il termine non è riconosciuto, restituisce ConstExpr(0) come fallback.
// ============================================================================

std::shared_ptr<Expression> HeuristicPropagator::parse_expression(
    Clingo::Symbol const &sym,
    std::unordered_map<std::string, AggregateKey> const &known_vars)
{
    // Caso 1: costante numerica
    if (sym.type() == Clingo::SymbolType::Number) {
        return std::make_shared<ConstExpr>(sym.number());
    }

    // Caso 2: simbolo funzionale
    if (sym.type() == Clingo::SymbolType::Function) {
        std::string name = sym.name();
        auto args = sym.arguments();

        // "self" (nessun argomento)
        if (name == "self" && args.size() == 0) {
            return std::make_shared<SelfExpr>();
        }

        // Operazione binaria: __add(a, b), __sub(a, b), __mul(a, b)
        if (is_binop_name(name) && args.size() == 2) {
            auto left = parse_expression(args[0], known_vars);
            auto right = parse_expression(args[1], known_vars);
            return std::make_shared<BinOpExpr>(binop_from_name(name),
                                                std::move(left), std::move(right));
        }

        // Variabile nota (atomo semplice senza argomenti il cui nome è in known_vars)
        if (args.size() == 0 && known_vars.find(name) != known_vars.end()) {
            return std::make_shared<VarExpr>(name);
        }

        // Atomo semplice senza argomenti non riconosciuto come variabile:
        // potrebbe essere un riferimento futuro o un errore, fallback a 0
        if (args.size() == 0) {
            return std::make_shared<ConstExpr>(0);
        }
    }

    // Fallback: costante 0
    return std::make_shared<ConstExpr>(0);
}

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
// ============================================================================
//
// Formato ASP: __heuristic(TargetPred, ...args...).
//
// Il primo argomento è sempre il predicato target.
// Gli argomenti successivi vengono classificati automaticamente:
//   - atomo semplice senza prefisso  → body positivo (es. x)
//   - prefisso __n_                  → body negativo (es. __n_c → c)
//   - __bind(var, __agg(pred))       → binding variabile → aggregato
//   - __weight(expr)                 → espressione per il peso
//   - __priority(expr)               → espressione per la priorità
//   - "true" / "false" / "sign"      → segno dell'euristica
//
// Esempio: __heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).
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
        tmpl.sign = "true"; // default sign

        // Prima passata: raccogliamo i __bind per popolare known_vars
        // prima di poter parsare le espressioni in __weight/__priority
        for (size_t i = 1; i < args.size(); ++i) {
            auto const &arg = args[i];
            if (arg.type() != Clingo::SymbolType::Function) continue;

            std::string arg_name = arg.name();
            auto arg_args = arg.arguments();

            if (arg_name == "__bind" && arg_args.size() == 2) {
                // __bind(var, __agg(pred)) o __bind(var, __agg(pred, idx))
                // arg_args[0] = var (simbolo semplice)
                // arg_args[1] = __agg(pred) (funzione aggregata)
                if (arg_args[0].type() == Clingo::SymbolType::Function &&
                    arg_args[0].arguments().size() == 0 &&
                    arg_args[1].type() == Clingo::SymbolType::Function) {

                    std::string var_name = arg_args[0].name();
                    std::string agg_op = arg_args[1].name();
                    auto agg_inner_args = arg_args[1].arguments();

                    if (is_aggregate_name(agg_op) && agg_inner_args.size() >= 1 &&
                        agg_inner_args[0].type() == Clingo::SymbolType::Function) {

                        std::string pred = agg_inner_args[0].name();
                        int arg_idx = -1;
                        if (agg_inner_args.size() >= 2 &&
                            agg_inner_args[1].type() == Clingo::SymbolType::Number) {
                            arg_idx = agg_inner_args[1].number();
                        }

                        AggregateKey key{agg_op, pred, arg_idx};
                        tmpl.local_vars[var_name] = key;
                        aggregate_preds.insert(pred);
                    }
                }
            }
        }

        // Seconda passata: classificazione completa degli argomenti
        // (ora known_vars è popolato e possiamo parsare le espressioni)
        for (size_t i = 1; i < args.size(); ++i) {
            auto const &arg = args[i];

            if (arg.type() == Clingo::SymbolType::Number) {
                // Numero intero "nudo" (fuori da __weight/__priority):
                // Per retrocompatibilità con argomenti semplici come weight costante,
                // se non c'è un __weight esplicito, usiamo questo come weight
                if (!tmpl.weight_expr) {
                    tmpl.weight_expr = std::make_shared<ConstExpr>(arg.number());
                }

            } else if (arg.type() == Clingo::SymbolType::Function) {
                std::string arg_name = arg.name();
                auto arg_args = arg.arguments();

                if (arg_name == "__bind") {
                    // Già processato nella prima passata
                    continue;

                } else if (arg_name == "__weight" && arg_args.size() == 1) {
                    // __weight(expr) → espressione per il peso
                    tmpl.weight_expr = parse_expression(arg_args[0], tmpl.local_vars);

                } else if (arg_name == "__priority" && arg_args.size() == 1) {
                    // __priority(expr) → espressione per la priorità
                    tmpl.priority_expr = parse_expression(arg_args[0], tmpl.local_vars);

                } else if (is_sign_name(arg_name) && arg_args.size() == 0) {
                    // Sign: true, false, sign
                    tmpl.sign = arg_name;

                } else if (arg_name == "self" && arg_args.size() == 0) {
                    // "self" come argomento top-level (retrocompatibilità)
                    // Se non c'è __weight esplicito, usa self come weight
                    if (!tmpl.weight_expr) {
                        tmpl.weight_expr = std::make_shared<SelfExpr>();
                    }

                } else if (is_neg_body(arg_name) && arg_args.size() == 0) {
                    // Body negativo: __n_c → c
                    std::string real_pred = strip_neg_prefix(arg_name);
                    tmpl.neg_body_preds.push_back(real_pred);
                    neg_body_preds.insert(real_pred);

                } else if (arg_args.size() == 0 && !is_aggregate_name(arg_name)) {
                    // Body positivo: atomo semplice senza prefisso speciale
                    tmpl.pos_body_preds.push_back(arg_name);
                    body_preds.insert(arg_name);
                }
                // Se ha argomenti ma non è riconosciuto, lo ignoriamo
            }
        }

        // Default: se nessun __weight specificato, weight = 0
        if (!tmpl.weight_expr) {
            tmpl.weight_expr = std::make_shared<ConstExpr>(0);
        }

        // Default: se nessun __priority specificato, priority = 0
        if (!tmpl.priority_expr) {
            tmpl.priority_expr = std::make_shared<ConstExpr>(0);
        }

        // Registra il predicato target
        target_preds.insert(tmpl.target_pred);

        // Crea gli stati aggregati per tutti i binding
        for (auto const &[var_name, agg_key] : tmpl.local_vars) {
            if (aggregate_states_.find(agg_key) == aggregate_states_.end()) {
                auto state = make_aggregate(agg_key.op);
                if (state) {
                    aggregate_states_[agg_key] = std::move(state);
                }
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
    // Iteriamo su tutti i local_vars di ogni template per trovare
    // i predicati da osservare per gli aggregati.

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
        for (auto const &[var_name, agg_key] : tmpl.local_vars) {
            register_agg_watches(agg_key);
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
                    LazyTargetInstance inst;
                    inst.target_lit = trigger.target_lit;
                    inst.neg_body_lits = trigger.neg_body_lits;
                    inst.domain_value = trigger.domain_value;
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
        // Per ciascuna, costruiamo l'environment dalle variabili locali
        // del template e valutiamo le espressioni AST per peso e priorità.

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

                // Costruzione dell'environment per la valutazione delle espressioni
                auto const &tmpl = rule_templates_[inst.rule_idx];
                std::unordered_map<std::string, int> env;

                // Inserisci il domain_value come "__self__" (usato da SelfExpr)
                env["__self__"] = inst.domain_value;

                // Risolvi tutte le variabili locali dai loro aggregati
                for (auto const &[var_name, agg_key] : tmpl.local_vars) {
                    int val = 0;
                    auto state_it = aggregate_states_.find(agg_key);
                    if (state_it != aggregate_states_.end()) {
                        val = state_it->second->result();
                    }
                    env[var_name] = val;
                }

                // Valutazione delle espressioni AST
                int current_priority = tmpl.priority_expr
                    ? tmpl.priority_expr->evaluate(env) : 0;
                int current_weight = tmpl.weight_expr
                    ? tmpl.weight_expr->evaluate(env) : 0;

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