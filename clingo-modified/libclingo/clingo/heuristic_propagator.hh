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
// LAZY HEURISTIC PROPAGATOR — Versione MVP (Minimum Viable Product)
// ============================================================================
//
// Questo propagatore implementa euristiche di dominio con valutazione lazy
// degli aggregati per Clingo. Invece di usare la direttiva #heuristic
// standard (che richiede grounding completo degli aggregati), le euristiche
// vengono specificate tramite fatti __heuristic/N e gli aggregati vengono
// valutati incrementalmente a runtime.
//
// Questa versione è volutamente semplice e lineare, pensata per essere
// facile da leggere e spiegare. Sacrifica performance per chiarezza:
// niente cache, niente string interning, niente pre-allocazioni.
//
// ============================================================================


// ============================================================================
// AggregateState — Classe base per gli aggregati dinamici
// ============================================================================
// Ogni aggregato (sum, count, min, max) ha uno stato che viene aggiornato
// incrementalmente: add() quando un atomo diventa vero, remove() durante
// il backtracking. result() restituisce il valore corrente.
//
// L'uso del polimorfismo qui è giustificato: ci sono 4 comportamenti
// diversi e il codice chiamante non deve conoscere il tipo concreto.
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

/// __min: valore minimo tra gli atomi attualmente veri.
/// Usa un multiset implicito (mappa valore→conteggio) per gestire
/// correttamente il backtracking quando ci sono valori duplicati.
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

/// Factory: crea lo stato aggregato appropriato dal nome dell'operazione.
/// Restituisce nullptr se il nome non è riconosciuto.
inline std::unique_ptr<AggregateState> make_aggregate(std::string const &op_name) {
    if (op_name == "__sum")   return std::make_unique<SumState>();
    if (op_name == "__count") return std::make_unique<CountState>();
    if (op_name == "__min")   return std::make_unique<MinState>();
    if (op_name == "__max")   return std::make_unique<MaxState>();
    return nullptr;
}

// ============================================================================
// AggregateKey — Identifica univocamente un aggregato
// ============================================================================
// Un aggregato è identificato dalla terna:
//   (nome_operazione, nome_predicato, indice_argomento)
//
// Esempio: ("__sum", "c", -1) identifica la somma di tutti i c(X) veri,
// dove il valore numerico è l'ultimo argomento di c/1.
//
// Versione MVP: usa direttamente stringhe come chiavi.
// (La versione ottimizzata usa ID interi tramite string interning.)
// ============================================================================

struct AggregateKey {
    std::string op_name;    // Tipo di aggregato: "__sum", "__count", ecc.
    std::string pred_name;  // Nome del predicato sorgente (es. "c")
    int arg_index = -1;     // Indice 0-based dell'argomento numerico (-1 = ultimo)

    bool operator==(AggregateKey const &o) const {
        return op_name == o.op_name && pred_name == o.pred_name && arg_index == o.arg_index;
    }
};

/// Hash per AggregateKey — combina gli hash delle 3 componenti
struct AggregateKeyHash {
    std::size_t operator()(AggregateKey const &k) const {
        std::size_t h = 17;
        h = h * 31 + std::hash<std::string>{}(k.op_name);
        h = h * 31 + std::hash<std::string>{}(k.pred_name);
        h = h * 31 + std::hash<int>{}(k.arg_index);
        return h;
    }
};

// ============================================================================
// Semantica del segno per la decisione euristica
// ============================================================================

enum class HeuristicSign { True, False, FollowFallback };

// ============================================================================
// HeuristicRuleTemplate — Template di una regola euristica
// ============================================================================
// Rappresenta una regola letta da __heuristic/N. Non contiene istanze
// concrete, ma la "forma" della regola che verrà istanziata a runtime
// quando un body positivo diventa vero.
//
// Esempio ASP:
//   __heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).
//
// Produce un template con:
//   target_pred = "b"
//   pos_body_preds = {"x"}
//   neg_body_preds = {"c"}
//   var_bindings = {"s" -> AggregateKey("__sum", "c", -1)}
//   weight_term = Symbol per "self"
//   priority_term = Symbol per "s"
//   sign = True
//
// Versione MVP: salva i Symbol Clingo originali per weight e priority,
// che vengono valutati ricorsivamente a runtime in decide().
// (La versione ottimizzata li compila in un AST Expression a init-time.)
// ============================================================================

struct HeuristicRuleTemplate {
    std::string target_pred;                  // Predicato target (es. "b")
    std::vector<std::string> pos_body_preds;  // Body positivi (es. {"x"})
    std::vector<std::string> neg_body_preds;  // Body negativi (es. {"c"} da __n_c)
    HeuristicSign sign = HeuristicSign::True; // Segno: true, false, sign

    // Bindings: mappa nome_variabile -> chiave dell'aggregato associato.
    // Es: {"s" -> AggregateKey("__sum", "c", -1)}
    std::unordered_map<std::string, AggregateKey> var_bindings;

    // Termini Clingo originali per peso e priorità.
    // Vengono valutati a runtime dalla funzione evaluate_term().
    // Se non specificati, il default è il Symbol numerico 0.
    Clingo::Symbol weight_term;
    Clingo::Symbol priority_term;
};

// ============================================================================
// LazyTargetInstance — Istanza euristica creata dinamicamente
// ============================================================================
// Quando un body positivo (es. x(27)) diventa vero durante propagate(),
// il propagatore crea un'istanza per ogni template che matcha.
// L'istanza contiene il literal del target (es. b(27)) e il domain value
// (es. 27) necessario per valutare le espressioni.
//
// Versione MVP: nessuna cache. Peso e priorità sono ricalcolati
// ogni volta che decide() viene chiamato.
// ============================================================================

struct LazyTargetInstance {
    Clingo::literal_t target_lit;   // Literal del target (es. b(27))
    int domain_value;               // Valore del dominio (es. 27)
    size_t rule_idx;                // Indice del template in rule_templates_
    size_t trigger_index;           // Indice nel vettore body_triggers_[body_lit]
};

// ============================================================================
// HeuristicPropagator — Il propagatore principale
// ============================================================================
// Implementa l'interfaccia Clingo::Heuristic con 4 metodi:
//
//   init()      — Parsare i fatti __heuristic/N e configurare i watch
//   propagate() — Aggiornare aggregati e creare istanze lazy
//   undo()      — Backtracking: rollback aggregati e rimuovere istanze
//   decide()    — Scegliere il miglior atomo target (hot path)
//
// Il flusso è:
//   1. init() legge i template e prepara le strutture dati
//   2. Il solver assegna letterali → propagate() aggiorna lo stato
//   3. Il solver fa backtrack → undo() ripristina lo stato
//   4. Il solver chiede una decisione → decide() suggerisce il miglior target
// ============================================================================

class HeuristicPropagator : public Clingo::Heuristic {

private:

    // --- Contributo di un atomo verso un aggregato ---
    // Quando l'atomo c(27) diventa vero, contribuisce con valore 27
    // verso l'aggregato __sum(c).
    struct WatchedAtomContribution {
        AggregateKey key;
        int value;
    };

    /// Info su un atomo osservato: lista di contributi verso aggregati.
    /// Un singolo atomo può contribuire a più aggregati contemporaneamente.
    struct WatchedAtomInfo {
        std::vector<WatchedAtomContribution> contributions;
    };

    /// Mappa: solver_literal → info sui contributi verso aggregati
    std::unordered_map<Clingo::literal_t, WatchedAtomInfo> watched_atoms_;

    // === Template delle regole euristiche ===
    std::vector<HeuristicRuleTemplate> rule_templates_;

    /// Info pre-calcolata per ogni body literal + template + domain value.
    /// Creata in init() per evitare lookup ripetuti a runtime.
    struct BodyTriggerInfo {
        size_t rule_idx;                                // Indice in rule_templates_
        int domain_value;                               // Es. 27 per x(27)
        Clingo::literal_t target_lit;                   // Es. b(27)
        std::vector<Clingo::literal_t> neg_body_lits;   // Es. {lit(c(27))}
    };

    /// Mappa: body_literal → lista di trigger attivabili.
    /// Quando il body_literal diventa vero, si attivano tutti i trigger.
    std::unordered_map<Clingo::literal_t, std::vector<BodyTriggerInfo>> body_triggers_;

    /// Istanze lazy create dinamicamente in propagate().
    /// Chiave: body_literal che ha causato la creazione.
    std::unordered_map<Clingo::literal_t, std::vector<LazyTargetInstance>> lazy_targets_;

    /// Set dei body literal attualmente attivi (per iterazione in decide).
    /// Versione MVP: semplice unordered_set, insert/erase O(1).
    /// (La versione ottimizzata usa un vector + position map per swap O(1).)
    std::unordered_set<Clingo::literal_t> active_body_lits_;

    /// Stati degli aggregati, indicizzati dalla chiave composita.
    /// Ogni stato viene aggiornato incrementalmente in propagate/undo.
    std::unordered_map<AggregateKey, std::unique_ptr<AggregateState>, AggregateKeyHash> aggregate_states_;

    // === Metodo helper privato ===
    void init_lazy_mode(Clingo::PropagateInit &init);

public:
    ~HeuristicPropagator() override = default;

    void init(Clingo::PropagateInit &init) override;
    void propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) override;
    void undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept override;
    Clingo::literal_t decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) noexcept override;
};