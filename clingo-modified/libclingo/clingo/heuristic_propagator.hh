#pragma once
#include <clingo.hh>
#include <unordered_map>
#include <vector>

class HeuristicPropagator : public Clingo::Heuristic {

private:
    // Mappa: literal della condizione osservata -> literal da forzare.
    // Esempio: h_watch(b) -> b.
    //
    // La chiave e il valore sono solver literals (non symbolic literals),
    // cosi' possono essere usati direttamente in assignment.truth_value().
    std::unordered_map<Clingo::literal_t, std::vector<Clingo::literal_t>> watched_to_targets_;

public:
    // Distruttore virtuale default (richiesto da ereditarieta' polimorfica).
    virtual ~HeuristicPropagator() = default;

    // Fase di inizializzazione del propagatore (prima della ricerca).
    // Qui costruiamo la mappa h_watch(X) -> X e registriamo i watch.
    void init(Clingo::PropagateInit &init) override;

    // Callback chiamata quando cambiano i watched literals.
    // Nel prototipo minimo non manteniamo stato incrementale.
    void propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) override;

    // Callback chiamata durante backtracking.
    // Nel prototipo minimo non c'e' stato da ripristinare.
    void undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept override;

    // Punto chiave dell'euristica: se una condizione h_watch e' vera,
    // prova a scegliere il relativo target ancora libero.
    // Se non trova candidati validi, ritorna 0 e lascia al solver la fallback.
    Clingo::literal_t decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) override;

};






