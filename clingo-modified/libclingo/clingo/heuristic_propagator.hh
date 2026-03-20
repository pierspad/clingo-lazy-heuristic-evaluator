#pragma once
#include <clingo.hh>
#include <vector>

class HeuristicPropagator : public Clingo::Heuristic {

private:
    // temp vector to save atom active in the trace
    std::vector<Clingo::literal_t> active_slits;

public:
    // Default virtual destructor
    virtual ~HeuristicPropagator() = default;

    // inspect the program before of the solving phase
    void init(Clingo::PropagateInit &init) override;

    // register changes of state when the watched literals become true
    void propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) override;

    // Removes literals from the data structure during backtracking
    void undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept override;

    // Forces heuristic atom selection or applies the default behaviour
    Clingo::literal_t decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) override;

};






