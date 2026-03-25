#include "clingo/heuristic_propagator.hh"
#include <algorithm>

void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    // Sicurezza: resettiamo la struttura dati ad ogni nuova inizializzazione.
    watched_to_targets_.clear();

    // In questa fase abbiamo accesso agli atomi simbolici del programma ground.
    auto atoms = init.symbolic_atoms();
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        // Cerchiamo solo atomi della forma h_watch/1.
        if (it->match("__heuristic", 4)) {
            // Leggiamo i 4 argomenti di __heuristic
            auto args = it->symbol().arguments();

            // cerchiamo e se X non esiste come atomo nel programma, non possiamo forzarlo.
            auto target_it = atoms.find(args[0]);
            if (target_it == atoms.end()) {
                continue;
            }

            // Conversione da symbolic literal a solver literal.
            // Solo i solver literals sono validi in decide()/assignment.
            Clingo::literal_t watched_lit = init.solver_literal(it->literal());
            Clingo::literal_t target_lit = init.solver_literal(target_it->literal());
            if (watched_lit == 0 || target_lit == 0) {
                // 0 indica conversione non valida/non disponibile.
                continue;
            }

            // Registriamo la condizione come watch: se cambia, clingo puo'
            // invocare propagate(). Nel prototipo attuale non usiamo propagate
            // per stato incrementale, ma il watch e' comunque coerente con il
            // design che userai nelle estensioni successive.
            init.add_watch(watched_lit);

            // Salviamo la regola euristica base:
            // quando watched_lit e' vero, proviamo a scegliere target_lit.
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
    // In questo prototipo non usiamo thread_id/fallback direttamente.
    // - thread_id: utile in versioni multi-thread con stato per thread.
    // - fallback: clingo lo usa automaticamente quando noi ritorniamo 0.
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

    // Nessuna scelta euristica applicabile: delega alla euristica standard.
    return 0;
}