#pragma once
#include <clingo.hh>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <string>
#include <memory>
#include <map>
#include <climits>

// ============================================================================
// AggregateState — Classe base astratta per aggregati dinamici
// ============================================================================
// Ogni sottoclasse implementa la logica di un singolo tipo di aggregato.
// Il propagatore non conosce mai il tipo concreto: usa solo questa interfaccia.
// ============================================================================

struct AggregateState {
    virtual ~AggregateState() = default;

    /// Chiamata quando un atomo osservato diventa vero (propagate)
    virtual void add(int value) = 0;

    /// Chiamata durante il backtracking (undo)
    virtual void remove(int value) = 0;

    /// Restituisce il valore corrente dell'aggregato
    virtual int result() const = 0;

    /// Riporta lo stato iniziale
    virtual void reset() = 0;
};

// ============================================================================
// Implementazioni concrete degli aggregati
// ============================================================================

/// __sum: somma dei valori degli atomi veri
struct SumState final : AggregateState {
    int total = 0;
    void add(int v) override    { total += v; }
    void remove(int v) override { total -= v; }
    int result() const override { return total; }
    void reset() override       { total = 0; }
};

/// __count: numero di atomi veri (il valore numerico è ignorato)
struct CountState final : AggregateState {
    int count = 0;
    void add(int) override      { ++count; }
    void remove(int) override   { --count; }
    int result() const override { return count; }
    void reset() override       { count = 0; }
};

/// __min: valore minimo tra gli atomi attualmente veri
/// Mantiene un multiset implicito tramite conteggio per supportare undo corretto
struct MinState final : AggregateState {
    std::map<int, int> active; // valore -> conteggio
    void add(int v) override    { active[v]++; }
    void remove(int v) override {
        auto it = active.find(v);
        if (it != active.end()) {
            if (--(it->second) == 0) active.erase(it);
        }
    }
    int result() const override {
        return active.empty() ? INT_MAX : active.begin()->first;
    }
    void reset() override { active.clear(); }
};

/// __max: valore massimo tra gli atomi attualmente veri
struct MaxState final : AggregateState {
    std::map<int, int> active; // valore -> conteggio
    void add(int v) override    { active[v]++; }
    void remove(int v) override {
        auto it = active.find(v);
        if (it != active.end()) {
            if (--(it->second) == 0) active.erase(it);
        }
    }
    int result() const override {
        return active.empty() ? INT_MIN : active.rbegin()->first;
    }
    void reset() override { active.clear(); }
};

// ============================================================================
// Factory function
// ============================================================================

/// Crea lo stato aggregato appropriato a partire dal nome dell'operazione.
/// Restituisce nullptr se il nome non è riconosciuto.
inline std::unique_ptr<AggregateState> make_aggregate(std::string const &op_name) {
    if (op_name == "__sum")   return std::make_unique<SumState>();
    if (op_name == "__count") return std::make_unique<CountState>();
    if (op_name == "__min")   return std::make_unique<MinState>();
    if (op_name == "__max")   return std::make_unique<MaxState>();
    return nullptr;
}

// ============================================================================
// Chiave composita per identificare un aggregato univocamente
// ============================================================================

/// Un aggregato è identificato dalla coppia (tipo_operazione, predicato).
/// Es: ("__sum", "c") è diverso da ("__count", "c").
struct AggregateKey {
    std::string op;     // Es: "__sum"
    std::string pred;   // Es: "c"
    int arg_index = -1; // Indice 0-based dell'argomento numerico (-1 = ultimo numerico)

    bool operator==(AggregateKey const &o) const {
        return op == o.op && pred == o.pred && arg_index == o.arg_index;
    }
};

/// Hash per AggregateKey per l'uso in unordered_map
struct AggregateKeyHash {
    std::size_t operator()(AggregateKey const &k) const {
        auto h1 = std::hash<std::string>{}(k.op);
        auto h2 = std::hash<std::string>{}(k.pred);
        auto h3 = std::hash<int>{}(k.arg_index);
        return h1 ^ (h2 << 1) ^ (h3 << 2);
    }
};

// ============================================================================
// STRUTTURE PER IL LAZY GROUNDING
// ============================================================================

/// Template di una regola euristica (letto da __heuristic_rule/7).
/// NON contiene istanziazioni concrete, solo la "forma" della regola.
///
/// Formato ASP:
///   __heuristic_rule(RuleID, TargetPred, BodyPred, NegBodyPred,
///                    WeightSource, PrioritySpec, Sign)
///
/// Esempio:
///   __heuristic_rule(r1, b, x, c, self, __sum(c), true).
///
/// Significato: "Per ogni X t.c. BodyPred(X) è vero e NegBodyPred(X) non è vero,
///               suggerisci TargetPred(X) con weight=X e priority=PrioritySpec"
struct HeuristicRuleTemplate {
    std::string rule_id;        // Identificatore univoco (es. "r1")
    std::string target_pred;    // Predicato target (es. "b")
    std::string body_pred;      // Predicato positivo del body (es. "x")
    std::string neg_body_pred;  // Predicato negativo del body (es. "c")
    std::string weight_source;  // "self" = usa il valore dell'atomo, oppure intero
    AggregateKey agg_key;       // Chiave dell'aggregato per la priority
    std::string sign;           // "true", "false", "sign"
};

/// Istanza euristica creata dinamicamente durante propagate.
/// Equivale al TargetInfo della modalità statica ma generata on-demand.
struct LazyTargetInstance {
    Clingo::literal_t target_lit;     // Literal del target (es. b(27))
    Clingo::literal_t neg_body_lit;   // Literal per il check negativo (es. c(27))
    int weight;                        // Peso estratto
    AggregateKey agg_key;              // Riferimento all'aggregato
    size_t rule_idx;                   // Indice del template che l'ha generata
};

// ============================================================================
// HeuristicPropagator
// ============================================================================

class HeuristicPropagator : public Clingo::Heuristic {

private:
    // === MODALITÀ STATICA (backward-compatible con __heuristic/4) ===

    /// Informazioni associate a ciascuna direttiva euristica target
    struct TargetInfo {
        Clingo::literal_t lit;           // Literal del target (es. b(X))
        Clingo::literal_t heuristic_lit; // Literal dell'atomo __heuristic(...) stesso
        int weight;
        AggregateKey agg_key;            // Chiave dell'aggregato usato come priority
    };

    /// Lista di tutti i target euristici estratti (modalità statica)
    std::vector<TargetInfo> heuristic_targets_;

    /// Info su un atomo osservato: a quali aggregati contribuisce e con quale valore
    struct WatchedAtomInfo {
        int value;                       // Valore numerico (es. 3 per c(3))
        std::vector<AggregateKey> keys;  // Aggregati a cui contribuisce
    };

    /// Mappa un solver_literal ai suoi aggregate di appartenenza
    std::unordered_map<Clingo::literal_t, WatchedAtomInfo> watched_atoms_;

    // === MODALITÀ LAZY (ground-on-demand con __heuristic_rule/7) ===

    /// Template delle regole euristiche
    std::vector<HeuristicRuleTemplate> rule_templates_;

    /// Mappa: body_literal → lista di (rule_index, valore_dominio) che possono
    /// essere triggerati quando quel body literal diventa vero.
    struct BodyTriggerInfo {
        size_t rule_idx;          // Indice in rule_templates_
        int domain_value;         // Il valore X del dominio (es. 27 per x(27))
        Clingo::literal_t target_lit;   // Literal target pre-risolto (es. b(27))
        Clingo::literal_t neg_body_lit; // Literal neg body pre-risolto (es. c(27))
    };
    std::unordered_map<Clingo::literal_t, std::vector<BodyTriggerInfo>> body_triggers_;

    /// Target euristici istanziati dinamicamente (generati in propagate).
    /// Chiave: body_literal che ha triggerato l'istanziazione.
    /// Ogni body_literal può generare più istanze (una per ogni template che matcha).
    std::unordered_map<Clingo::literal_t, std::vector<LazyTargetInstance>> lazy_targets_;

    /// Set dei body literal attivi (per iterazione efficiente in decide)
    std::vector<Clingo::literal_t> active_body_lits_;

    /// Flag: true se sono stati trovati template __heuristic_rule/7
    bool has_lazy_rules_ = false;

    // === CONDIVISO tra le due modalità ===

    /// Mappa gli aggregate key ai loro stati dinamici (polimorfici)
    std::unordered_map<AggregateKey, std::unique_ptr<AggregateState>, AggregateKeyHash> aggregate_states_;

    // === Metodi helper privati ===
    void init_static_mode(Clingo::PropagateInit &init);
    void init_lazy_mode(Clingo::PropagateInit &init);

public:
    virtual ~HeuristicPropagator() = default;

    void init(Clingo::PropagateInit &init) override;
    void propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) override;
    void undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept override;
    Clingo::literal_t decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) override;
};