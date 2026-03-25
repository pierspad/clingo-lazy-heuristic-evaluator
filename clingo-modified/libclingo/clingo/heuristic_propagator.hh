#pragma once
#include <clingo.hh>
#include <unordered_map>
#include <vector>
#include <string>

class HeuristicPropagator : public Clingo::Heuristic {

private:
    // Informazioni associate a ciascuna direttiva euristica target
    struct TargetInfo {
        Clingo::literal_t lit;
        int weight;
        std::string dynamic_op;   // Es: "__sum"
        std::string dynamic_pred; // Es: "c" oppure "b"
    };
    
    // Lista di tutti i target euristici estratti
    std::vector<TargetInfo> heuristic_targets_;

    // Associa un solver_literal osservato (es. c(2)) alla coppia <nome_predicato, valore_numerico>
    // Serve per generalizzare l'incremento/decremento nei metodi propagate e undo
    std::unordered_map<Clingo::literal_t, std::pair<std::string, int>> watched_aggregates_;

    // Stato dinamico online: mappa il nome del predicato alla sua somma corrente calcolata
    std::unordered_map<std::string, int> dynamic_sums_;

public:
    virtual ~HeuristicPropagator() = default;

    void init(Clingo::PropagateInit &init) override;
    void propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) override;
    void undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept override;
    Clingo::literal_t decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) override;
};