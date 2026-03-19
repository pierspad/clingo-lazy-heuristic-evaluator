#include "clingo/heuristic_propagator.hh"
#include <algorithm>
#include <iostream>

void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    auto atoms = init.symbolic_atoms();
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        if (it->match("h_watch", 1)) {
            Clingo::literal_t lit = it->literal();
            // Converte il letterale simbolico in letterale del solver
            Clingo::literal_t solver_lit = init.solver_literal(lit);
            init.add_watch(solver_lit);
        }
    }
}

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    for (auto lit : changes) {
        active_slits.push_back(lit);
    }
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    for (auto lit : changes) {
        // Corretto il nome della variabile in entrambi i parametri
        auto it = std::find(active_slits.begin(), active_slits.end(), lit);
        if (it != active_slits.end()) {
            active_slits.erase(it);
        }
    }
}

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) {
    if (!active_slits.empty()) {
        std::cout << "Forzatura euristica eseguita dal propagatore!" << std::endl;
        return active_slits.back();
    }
    return fallback;
}