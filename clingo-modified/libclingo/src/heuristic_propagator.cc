#include "clingo/heuristic_propagator.hh"
#include <algorithm>
#include <iostream>
#include <unordered_set>

// ============================================================================
// Funzioni utility — Parsing e conversione
// ============================================================================

/// Prova a interpretare un nome come segno euristico (true/false/sign).
static bool try_parse_sign(std::string const &name, HeuristicSign &out) {
    if (name == "true")  { out = HeuristicSign::True; return true; }
    if (name == "false") { out = HeuristicSign::False; return true; }
    if (name == "sign")  { out = HeuristicSign::FollowFallback; return true; }
    return false;
}

/// Controlla se un nome ha il prefisso __n_ (body negativo).
static bool is_neg_body(std::string const &name) {
    return name.size() > 4 && name.compare(0, 4, "__n_") == 0;
}

/// Rimuove il prefisso __n_ da un nome.
static std::string strip_neg_prefix(std::string const &name) {
    return name.substr(4);
}

/// Controlla se un nome è un operatore aggregato riconosciuto.
static bool is_aggregate_op(std::string const &name) {
    return name == "__sum" || name == "__count" || name == "__min" || name == "__max";
}

/// Estrae il valore numerico da un atomo Clingo.
/// Se arg_index >= 0, cerca l'N-esimo argomento numerico (0-based).
/// Se arg_index == -1, restituisce l'ultimo argomento numerico trovato.
static bool extract_numeric_argument(Clingo::Symbol const &symbol, int arg_index, int &value) {
    if (symbol.type() != Clingo::SymbolType::Function) return false;
    auto const args = symbol.arguments();
    if (args.empty()) return false;

    if (arg_index >= 0) {
        int numeric_pos = 0;
        for (auto const &arg : args) {
            if (arg.type() != Clingo::SymbolType::Number) continue;
            if (numeric_pos == arg_index) { value = arg.number(); return true; }
            ++numeric_pos;
        }
        return false;
    }

    bool found = false;
    for (auto const &arg : args) {
        if (arg.type() == Clingo::SymbolType::Number) { value = arg.number(); found = true; }
    }
    return found;
}

/// Applica il segno euristico al literal target.
static Clingo::literal_t apply_sign(HeuristicSign sign, Clingo::literal_t target_lit, Clingo::literal_t fallback) {
    switch (sign) {
        case HeuristicSign::True:  return target_lit;
        case HeuristicSign::False: return -target_lit;
        case HeuristicSign::FollowFallback: return fallback < 0 ? -target_lit : target_lit;
    }
    return target_lit;
}

// ============================================================================
// evaluate_term() — Valutazione ricorsiva di un termine Clingo
// ============================================================================
// Questa funzione valuta un Clingo::Symbol come espressione aritmetica.
// Sostituisce l'intero AST Expression della versione ottimizzata.
//
// Tipi supportati:
//   - Numero intero → restituisce il valore
//   - "self"        → restituisce il domain_value dell'istanza
//   - Variabile     → cerca il valore nella mappa var_env
//   - __add(a, b)   → valuta ricorsivamente a + b
//   - __sub(a, b)   → valuta ricorsivamente a - b
//   - __mul(a, b)   → valuta ricorsivamente a * b
//
// Versione MVP: confronti stringa ad ogni chiamata.
// (La versione ottimizzata compila il termine in un AST una sola volta.)
// ============================================================================

static int evaluate_term(Clingo::Symbol const &term, int domain_value,
                         std::unordered_map<std::string, int> const &var_env) {
    // Caso base: numero intero
    if (term.type() == Clingo::SymbolType::Number) {
        return term.number();
    }

    // Deve essere una funzione
    if (term.type() != Clingo::SymbolType::Function) {
        return 0;
    }

    std::string const name = term.name();
    auto const args = term.arguments();

    // Keyword "self": restituisce il domain value (es. 27 per b(27))
    if (name == "self" && args.empty()) {
        return domain_value;
    }

    // Operazioni binarie: __add, __sub, __mul
    if (args.size() == 2) {
        if (name == "__add") {
            return evaluate_term(args[0], domain_value, var_env) +
                   evaluate_term(args[1], domain_value, var_env);
        }
        if (name == "__sub") {
            return evaluate_term(args[0], domain_value, var_env) -
                   evaluate_term(args[1], domain_value, var_env);
        }
        if (name == "__mul") {
            return evaluate_term(args[0], domain_value, var_env) *
                   evaluate_term(args[1], domain_value, var_env);
        }
    }

    // Variabile: cerca nella mappa dei binding
    if (args.empty()) {
        auto it = var_env.find(name);
        if (it != var_env.end()) {
            return it->second;
        }
        std::cerr << "[heuristic_propagator] variabile '" << name
                  << "' non trovata in evaluate_term, uso 0.\n";
    }

    return 0;
}

// ============================================================================
// init() — Punto di ingresso dell'inizializzazione
// ============================================================================

void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    // Reset completo di tutte le strutture dati
    aggregate_states_.clear();
    watched_atoms_.clear();
    rule_templates_.clear();
    body_triggers_.clear();
    lazy_targets_.clear();
    active_body_lits_.clear();

    // Cerca se ci sono fatti __heuristic nei symbolic atoms
    auto atoms = init.symbolic_atoms();
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        if (it->symbol().name() == "__heuristic") {
            init_lazy_mode(init);
            return;
        }
    }
}

// ============================================================================
// init_lazy_mode() — Parsing e setup completo (flusso lineare)
// ============================================================================
// Questa funzione esegue tutto il setup in un unico flusso sequenziale:
//
//   1. Scansiona gli atomi simbolici e parsa ogni __heuristic/N
//   2. Raccoglie i predicati necessari (body, target, neg, aggregati)
//   3. Costruisce la mappa predicato+domainValue → solver_literal
//   4. Crea i body triggers (collegamento body_lit → template + target)
//   5. Registra i watch sugli atomi degli aggregati
//
// Versione MVP: tutto inline, niente struct helper separate.
// ============================================================================

void HeuristicPropagator::init_lazy_mode(Clingo::PropagateInit &init) {
    auto atoms = init.symbolic_atoms();

    // === Set di predicati che dovremo risolvere in literal ===
    std::unordered_set<std::string> all_body_preds;
    std::unordered_set<std::string> all_target_preds;
    std::unordered_set<std::string> all_neg_preds;
    std::unordered_set<std::string> all_agg_preds;

    // ---------------------------------------------------------------
    // FASE 1: Parsing dei template __heuristic/N
    // ---------------------------------------------------------------
    // Per ogni fatto __heuristic(...) trovato, classifichiamo gli argomenti
    // e costruiamo un HeuristicRuleTemplate.

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const symbol = it->symbol();
        if (symbol.type() != Clingo::SymbolType::Function ||
            symbol.name() != "__heuristic") {
            continue;
        }

        auto const args = symbol.arguments();
        if (args.size() < 2) {
            std::cerr << "[heuristic_propagator] __heuristic malformato: "
                      << "atteso almeno __heuristic(target, arg, ...), ignorato.\n";
            continue;
        }

        // Il primo argomento deve essere il predicato target (atomo nullario)
        if (args[0].type() != Clingo::SymbolType::Function || !args[0].arguments().empty()) {
            std::cerr << "[heuristic_propagator] __heuristic malformato: "
                      << "il primo argomento deve essere un predicato nullo (es. b), ignorato.\n";
            continue;
        }

        HeuristicRuleTemplate tmpl;
        tmpl.target_pred = args[0].name();
        tmpl.sign = HeuristicSign::True;

        // Default per weight e priority: numero 0
        tmpl.weight_term = Clingo::Number(0);
        tmpl.priority_term = Clingo::Number(0);

        // Parsa gli argomenti dal secondo in poi
        for (size_t i = 1; i < args.size(); ++i) {
            auto const &arg = args[i];

            // --- Numeri letterali (legacy: usato come peso) ---
            if (arg.type() == Clingo::SymbolType::Number) {
                tmpl.weight_term = arg;
                continue;
            }

            if (arg.type() != Clingo::SymbolType::Function) {
                continue;
            }

            std::string const arg_name = arg.name();
            auto const arg_args = arg.arguments();

            // --- __bind(var, __agg(pred)) → binding variabile → aggregato ---
            if (arg_name == "__bind" && arg_args.size() == 2) {
                if (arg_args[0].type() != Clingo::SymbolType::Function ||
                    !arg_args[0].arguments().empty() ||
                    arg_args[1].type() != Clingo::SymbolType::Function) {
                    std::cerr << "[heuristic_propagator] __bind malformato, ignorato.\n";
                    continue;
                }

                std::string const var_name = arg_args[0].name();
                std::string const agg_op = arg_args[1].name();
                auto const agg_inner = arg_args[1].arguments();

                if (!is_aggregate_op(agg_op) || agg_inner.empty() ||
                    agg_inner[0].type() != Clingo::SymbolType::Function) {
                    std::cerr << "[heuristic_propagator] aggregato non valido in __bind("
                              << var_name << ", ...), ignorato.\n";
                    continue;
                }

                std::string const pred = agg_inner[0].name();
                int arg_idx = -1;
                if (agg_inner.size() >= 2 && agg_inner[1].type() == Clingo::SymbolType::Number) {
                    arg_idx = agg_inner[1].number();
                }

                AggregateKey key{agg_op, pred, arg_idx};
                tmpl.var_bindings[var_name] = key;
                all_agg_preds.insert(pred);

                // Crea lo stato aggregato se non esiste già
                if (aggregate_states_.find(key) == aggregate_states_.end()) {
                    if (auto state = make_aggregate(agg_op)) {
                        aggregate_states_.emplace(key, std::move(state));
                    }
                }
                continue;
            }

            // --- __weight(expr) → termine per il peso ---
            if (arg_name == "__weight" && arg_args.size() == 1) {
                tmpl.weight_term = arg_args[0];
                continue;
            }

            // --- __priority(expr) → termine per la priorità ---
            if (arg_name == "__priority" && arg_args.size() == 1) {
                tmpl.priority_term = arg_args[0];
                continue;
            }

            // --- Atomi semplici (senza argomenti) ---
            if (arg_args.empty()) {
                // Segno: true, false, sign
                HeuristicSign parsed_sign;
                if (try_parse_sign(arg_name, parsed_sign)) {
                    tmpl.sign = parsed_sign;
                    continue;
                }

                // "self" standalone (legacy: usato come peso)
                if (arg_name == "self") {
                    tmpl.weight_term = arg;
                    continue;
                }

                // Body negativo: __n_pred → "not pred"
                if (is_neg_body(arg_name)) {
                    std::string const real_pred = strip_neg_prefix(arg_name);
                    tmpl.neg_body_preds.push_back(real_pred);
                    all_neg_preds.insert(real_pred);
                    continue;
                }

                // Body positivo (al massimo uno per template)
                if (tmpl.pos_body_preds.empty()) {
                    tmpl.pos_body_preds.push_back(arg_name);
                    all_body_preds.insert(arg_name);
                }
                continue;
            }
        }

        all_target_preds.insert(tmpl.target_pred);
        rule_templates_.push_back(std::move(tmpl));
    }

    if (rule_templates_.empty()) return;

    // ---------------------------------------------------------------
    // FASE 2: Costruzione della mappa predicato → (domainValue → literal)
    // ---------------------------------------------------------------
    // Scansioniamo tutti gli atomi simbolici e per ogni predicato
    // di interesse, mappiamo (predicato, domainValue) al solver literal.

    using PredLitMap = std::unordered_map<std::string, std::unordered_map<int, Clingo::literal_t>>;
    PredLitMap pred_lit_map;

    std::unordered_set<std::string> all_preds;
    all_preds.insert(all_body_preds.begin(), all_body_preds.end());
    all_preds.insert(all_target_preds.begin(), all_target_preds.end());
    all_preds.insert(all_neg_preds.begin(), all_neg_preds.end());
    all_preds.insert(all_agg_preds.begin(), all_agg_preds.end());

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const pname = it->symbol().name();
        if (all_preds.find(pname) == all_preds.end()) continue;

        auto const sym_args = it->symbol().arguments();
        if (sym_args.empty()) continue;

        int domain_val = 0;
        if (!extract_numeric_argument(it->symbol(), 0, domain_val)) continue;

        Clingo::literal_t slit = init.solver_literal(it->literal());
        if (slit != 0) {
            pred_lit_map[pname][domain_val] = slit;
        }
    }

    // ---------------------------------------------------------------
    // FASE 3: Costruzione dei body triggers
    // ---------------------------------------------------------------
    // Per ogni template, per ogni domain value del body positivo,
    // creiamo un BodyTriggerInfo che collega body_lit → target_lit.

    for (size_t ri = 0; ri < rule_templates_.size(); ++ri) {
        auto const &tmpl = rule_templates_[ri];
        if (tmpl.pos_body_preds.empty()) continue;

        auto body_it = pred_lit_map.find(tmpl.pos_body_preds[0]);
        if (body_it == pred_lit_map.end()) continue;

        auto target_map_it = pred_lit_map.find(tmpl.target_pred);

        for (auto const &entry : body_it->second) {
            int const domain_val = entry.first;
            Clingo::literal_t const body_lit = entry.second;

            // Risolvi il target literal per questo domain value
            Clingo::literal_t target_lit = 0;
            if (target_map_it != pred_lit_map.end()) {
                auto tit = target_map_it->second.find(domain_val);
                if (tit != target_map_it->second.end()) {
                    target_lit = tit->second;
                }
            }
            if (target_lit == 0) continue;

            // Risolvi i neg body literals
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

    // ---------------------------------------------------------------
    // FASE 4: Registrazione watch sugli atomi degli aggregati
    // ---------------------------------------------------------------
    // Per ogni aggregato usato nei template, troviamo tutti gli atomi
    // del predicato sorgente e li mettiamo in watch. Quando diventano
    // veri, propagate() aggiornerà lo stato dell'aggregato.

    for (auto const &tmpl : rule_templates_) {
        for (auto const &vb : tmpl.var_bindings) {
            AggregateKey const &agg_key = vb.second;

            for (auto it = atoms.begin(); it != atoms.end(); ++it) {
                auto const sym = it->symbol();
                if (sym.name() != agg_key.pred_name) continue;

                int value = 0;
                if (!extract_numeric_argument(sym, agg_key.arg_index, value)) continue;

                Clingo::literal_t const slit = init.solver_literal(it->literal());
                if (slit == 0) continue;

                init.add_watch(slit);

                // Registra il contributo di questo atomo verso l'aggregato
                auto &watch_info = watched_atoms_[slit];
                bool already = false;
                for (auto const &c : watch_info.contributions) {
                    if (c.key == agg_key) { already = true; break; }
                }
                if (!already) {
                    watch_info.contributions.push_back(WatchedAtomContribution{agg_key, value});
                }
            }
        }
    }
}

// ============================================================================
// propagate() — Aggiornamento incrementale degli aggregati + istanziazione lazy
// ============================================================================

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    static_cast<void>(control);

    for (auto lit : changes) {
        // --- Aggiornamento aggregati ---
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            for (auto const &contrib : watch_it->second.contributions) {
                auto state_it = aggregate_states_.find(contrib.key);
                if (state_it != aggregate_states_.end()) {
                    state_it->second->add(contrib.value);
                }
            }
        }

        // --- Creazione istanze lazy ---
        auto trigger_it = body_triggers_.find(lit);
        if (trigger_it != body_triggers_.end()) {
            auto &target_vec = lazy_targets_[lit];
            target_vec.clear();

            for (size_t ti = 0; ti < trigger_it->second.size(); ++ti) {
                auto const &trigger = trigger_it->second[ti];

                LazyTargetInstance inst;
                inst.target_lit = trigger.target_lit;
                inst.domain_value = trigger.domain_value;
                inst.rule_idx = trigger.rule_idx;
                inst.trigger_index = ti;

                target_vec.push_back(std::move(inst));
            }

            if (!target_vec.empty()) {
                active_body_lits_.insert(lit);
            } else {
                active_body_lits_.erase(lit);
            }
        }
    }
}

// ============================================================================
// undo() — Backtracking: rollback aggregati e rimozione istanze lazy
// ============================================================================

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    static_cast<void>(control);

    for (auto lit : changes) {
        // --- Rollback aggregati ---
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            for (auto const &contrib : watch_it->second.contributions) {
                auto state_it = aggregate_states_.find(contrib.key);
                if (state_it != aggregate_states_.end()) {
                    state_it->second->remove(contrib.value);
                }
            }
        }

        // --- Rimozione istanze lazy ---
        auto lazy_it = lazy_targets_.find(lit);
        if (lazy_it != lazy_targets_.end() && !lazy_it->second.empty()) {
            lazy_it->second.clear();
            active_body_lits_.erase(lit);
        }
    }
}

// ============================================================================
// decide() — Scelta del miglior target euristico
// ============================================================================
// Itera su tutte le istanze lazy attive e seleziona quella con la
// combinazione (priorità, peso) più alta. Questa è la funzione chiamata
// più frequentemente dal solver (hot path).
//
// Per ogni istanza:
//   1. Verifica che i body negativi non siano soddisfatti
//   2. Verifica che il target sia ancora libero (non assegnato)
//   3. Costruisce l'environment delle variabili (da aggregati correnti)
//   4. Valuta peso e priorità con evaluate_term()
//   5. Confronta con il miglior candidato corrente
//
// Versione MVP: ricalcola tutto ad ogni chiamata, senza cache.
// ============================================================================

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

        // Accesso ai trigger per i neg_body_lits
        auto trigger_it = body_triggers_.find(body_lit);

        for (auto const &inst : lazy_it->second) {
            // --- Check body negativi ---
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

            // --- Check target libero ---
            if (assignment.truth_value(inst.target_lit) != Clingo::TruthValue::Free) {
                continue;
            }

            auto const &tmpl = rule_templates_[inst.rule_idx];

            // --- Costruzione environment variabili ---
            // Legge i valori correnti degli aggregati per ogni variabile
            // legata con __bind nel template.
            std::unordered_map<std::string, int> var_env;
            for (auto const &vb : tmpl.var_bindings) {
                int val = 0;
                auto state_it = aggregate_states_.find(vb.second);
                if (state_it != aggregate_states_.end()) {
                    val = state_it->second->result();
                }
                var_env[vb.first] = val;
            }

            // --- Valutazione peso e priorità ---
            int current_priority = evaluate_term(tmpl.priority_term, inst.domain_value, var_env);
            int current_weight = evaluate_term(tmpl.weight_term, inst.domain_value, var_env);

            // --- Selezione del migliore (priorità > peso come tiebreaker) ---
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

    if (!has_best || best_target == 0) {
        return 0;
    }
    return apply_sign(best_sign, best_target, fallback);
}
