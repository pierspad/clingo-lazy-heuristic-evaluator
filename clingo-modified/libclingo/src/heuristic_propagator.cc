#include "clingo/heuristic_propagator.hh"
#include <algorithm>

void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    heuristic_targets_.clear();
    watched_aggregates_.clear();
    dynamic_sums_.clear();

    auto atoms = init.symbolic_atoms();
    std::vector<std::string> predicates_to_watch;

    // --- PRIMA PASSATA: Estrazione delle direttive euristiche ---
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

            // 3. Priority Dinamica (arg[2], es. __dyn_sum(c))
            std::string op = "";
            std::string pred = "";

            if (args[2].type() == Clingo::SymbolType::Function) {
                op = args[2].name();
                auto op_args = args[2].arguments();
                if (op_args.size() == 1 && op_args[0].type() == Clingo::SymbolType::Function) {
                    pred = op_args[0].name();
                    
                    // Aggiungiamo il predicato interno alla lista di quelli da osservare globalmente
                    if (std::find(predicates_to_watch.begin(), predicates_to_watch.end(), pred) == predicates_to_watch.end()) {
                        predicates_to_watch.push_back(pred);
                        dynamic_sums_[pred] = 0; // Inizializza l'accumulatore
                    }
                }
            }

            heuristic_targets_.push_back({target_lit, weight, op, pred});
        }
    }

    // --- SECONDA PASSATA: Registrazione dei watch sugli aggregati ---
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        std::string pred_name = it->symbol().name();
        
        // Verifichiamo se l'atomo in esame appartiene a uno dei predicati richiesti dall'euristica
        if (std::find(predicates_to_watch.begin(), predicates_to_watch.end(), pred_name) != predicates_to_watch.end()) {
            auto args = it->symbol().arguments();
            
            // Assumiamo arità 1 per estrarre il valore numerico (es. l'1 in c(1))
            if (args.size() == 1 && args[0].type() == Clingo::SymbolType::Number) {
                Clingo::literal_t lit = init.solver_literal(it->literal());
                if (lit != 0) {
                    init.add_watch(lit); // Richiede a clingo di notificare propagate/undo
                    watched_aggregates_[lit] = {pred_name, args[0].number()};
                }
            }
        }
    }
}

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    static_cast<void>(control);
    
    // Aggiornamento additivo dello stato dinamico per i letterali diventati veri
    for (auto lit : changes) {
        auto it = watched_aggregates_.find(lit);
        if (it != watched_aggregates_.end()) {
            dynamic_sums_[it->second.first] += it->second.second;
        }
    }
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    static_cast<void>(control);

    // Rollback dello stato dinamico durante il backtracking
    for (auto lit : changes) {
        auto it = watched_aggregates_.find(lit);
        if (it != watched_aggregates_.end()) {
            dynamic_sums_[it->second.first] -= it->second.second;
        }
    }
}

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) {
    static_cast<void>(thread_id);
    static_cast<void>(fallback);

    Clingo::literal_t best_target = 0;
    int max_priority = -1; 
    int best_weight = -1;

    // Scansione dei target euristici per valutare le priority on the fly
    for (const auto& target_info : heuristic_targets_) {
        // Valutiamo solo i target che non hanno ancora un valore di verità assegnato
        if (assignment.truth_value(target_info.lit) == Clingo::TruthValue::Free) {
            
            // Lettura O(1) della somma calcolata a runtime per il predicato associato
            int current_priority = dynamic_sums_[target_info.dynamic_pred];

            // Aggiornamento del target ottimale: massimizziamo la priorità, e a parità di priorità il peso
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