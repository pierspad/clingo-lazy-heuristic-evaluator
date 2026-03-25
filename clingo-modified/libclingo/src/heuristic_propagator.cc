#include "clingo/heuristic_propagator.hh"

void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    heuristic_targets_.clear();
    aggregate_states_.clear();
    watched_atoms_.clear();

    auto atoms = init.symbolic_atoms();

    // Raccogliamo i predicati da osservare e i relativi aggregate key.
    // La struttura mappa: nome_predicato -> lista di AggregateKey che lo usano.
    // Es: "c" -> [("__sum","c"), ("__count","c")]
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

            // 3. Priority dinamica (arg[2], es. __sum(c), __count(c), __min(c), __max(c))
            AggregateKey agg_key{"", ""};

            if (args[2].type() == Clingo::SymbolType::Function) {
                std::string op_name = args[2].name();
                auto op_args = args[2].arguments();

                if (op_args.size() == 1 && op_args[0].type() == Clingo::SymbolType::Function) {
                    std::string pred = op_args[0].name();
                    agg_key = {op_name, pred};

                    // Crea lo stato aggregato se non esiste ancora per questa chiave
                    if (aggregate_states_.find(agg_key) == aggregate_states_.end()) {
                        auto state = make_aggregate(op_name);
                        if (state) {
                            aggregate_states_[agg_key] = std::move(state);
                            predicates_to_watch[pred].push_back(agg_key);
                        }
                    } else {
                        // Assicuriamoci che il predicato sia comunque registrato
                        auto &keys = predicates_to_watch[pred];
                        if (std::find(keys.begin(), keys.end(), agg_key) == keys.end()) {
                            keys.push_back(agg_key);
                        }
                    }
                }
            }

            heuristic_targets_.push_back({target_lit, weight, agg_key});
        }
    }

    // ---- SECONDA PASSATA: Registrazione dei watch sugli atomi aggregati ----
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        std::string pred_name = it->symbol().name();

        auto pred_it = predicates_to_watch.find(pred_name);
        if (pred_it == predicates_to_watch.end()) continue;

        auto args = it->symbol().arguments();

        // Assumiamo arità 1 per estrarre il valore numerico (es. 3 in c(3))
        if (args.size() == 1 && args[0].type() == Clingo::SymbolType::Number) {
            Clingo::literal_t lit = init.solver_literal(it->literal());
            if (lit != 0) {
                init.add_watch(lit);
                watched_atoms_[lit] = {args[0].number(), pred_it->second};
            }
        }
    }
}

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    static_cast<void>(control);

    for (auto lit : changes) {
        auto it = watched_atoms_.find(lit);
        if (it != watched_atoms_.end()) {
            auto const &info = it->second;
            for (auto const &key : info.keys) {
                auto state_it = aggregate_states_.find(key);
                if (state_it != aggregate_states_.end()) {
                    state_it->second->add(info.value);
                }
            }
        }
    }
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    static_cast<void>(control);

    for (auto lit : changes) {
        auto it = watched_atoms_.find(lit);
        if (it != watched_atoms_.end()) {
            auto const &info = it->second;
            for (auto const &key : info.keys) {
                auto state_it = aggregate_states_.find(key);
                if (state_it != aggregate_states_.end()) {
                    state_it->second->remove(info.value);
                }
            }
        }
    }
}

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) {
    static_cast<void>(thread_id);
    static_cast<void>(fallback);

    Clingo::literal_t best_target = 0;
    int max_priority = -1;
    int best_weight = -1;

    for (auto const &target_info : heuristic_targets_) {
        if (assignment.truth_value(target_info.lit) == Clingo::TruthValue::Free) {

            // Lettura O(1) del valore corrente dell'aggregato associato
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