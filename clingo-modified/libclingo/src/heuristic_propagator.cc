#include "clingo/heuristic_propagator.hh"
#include <algorithm>

void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    watched_to_targets_.clear();

    auto atoms = init.symbolic_atoms();
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        // Cerchiamo solo atomi della forma __heuristic/4.
        if (it->match("__heuristic", 4)) {
            // Leggiamo i 4 argomenti di __heuristic
            auto args = it->symbol().arguments();

            // args[0] = target (es. c)
            // args[1] = peso (es. 1)
            // args[2] = livello (es. 1)
            // args[3] = modificatore (es. true)

            // cerchiamo e se X non esiste come atomo nel programma, non possiamo forzarlo.
            auto target_it = atoms.find(args[0]);
            if (target_it == atoms.end()) {
                continue;
            }

            // watched literal è il letterale __heuristic(<term>, <weight>, <priority>, <sign>) 
            // target literal è il <term>
            Clingo::literal_t watched_lit = init.solver_literal(it->literal());
            Clingo::literal_t target_lit = init.solver_literal(target_it->literal());
            if (watched_lit == 0 || target_lit == 0) {
                continue;
            }

            //clingo invoca propagate quando cambia il watched
            init.add_watch(watched_lit);

            // mappa di <slit,vector<slit>>
            // ogni watched ha un vettore di target slit associati
            watched_to_targets_[watched_lit].push_back(target_lit);
        }
    }
}

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    // Placeholder esplicito: in questo prototipo non aggiorniamo stato online.
    // Manteniamo il metodo per compatibilita' con l'interfaccia Heuristic.
    static_cast<void>(control);
    static_cast<void>(changes);
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    // Placeholder esplicito: non avendo stato incrementale, non c'e' nulla da undo.
    static_cast<void>(control);
    static_cast<void>(changes);
}

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) {
    static_cast<void>(thread_id);
    static_cast<void>(fallback);

    // Cerchiamo una condizione watch attualmente vera.
    for (auto const &entry : watched_to_targets_) {
        if (assignment.truth_value(entry.first) != Clingo::TruthValue::True) {
            continue;
        }

        // Se la condizione e' vera, proviamo i target associati.
        // Vincolo fondamentale: decide deve restituire un literal libero.
        for (auto target_lit : entry.second) {
            if (assignment.truth_value(target_lit) == Clingo::TruthValue::Free) {
                return target_lit;
            }
        }
    }

    return 0;
}