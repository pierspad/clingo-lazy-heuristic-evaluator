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
// EXPRESSION AST — Albero di espressioni per peso e priorità
// ============================================================================
// L'AST permette di esprimere calcoli come S+1, S*10, ecc.
// dove S è una variabile locale legata a un aggregato tramite __bind.
//
// OTTIMIZZAZIONE: le variabili sono indicizzate con interi (non stringhe).
// L'environment a runtime è un flat array int[] dove:
//   - env[0] = __self__ (domain_value)
//   - env[1] = prima variabile locale
//   - env[2] = seconda variabile locale
//   - ...
//
// Questo elimina ogni allocazione dinamica e hash lookup dall'hot path.
// ============================================================================

/// Indice riservato per il domain value (__self__)
static constexpr int ENV_SELF_INDEX = 0;

/// Tipo di operazione binaria
enum class BinOp { ADD, SUB, MUL };

/// Classe base astratta per un nodo dell'albero di espressioni.
/// L'environment è un flat array di interi: env[i] è il valore della variabile i.
struct Expression {
    virtual ~Expression() = default;
    virtual int evaluate(int const *env) const = 0;
    virtual bool depends_on_bindings() const = 0;
};

/// Foglia: costante numerica (es. 1, 5, 0)
struct ConstExpr final : Expression {
    int value;
    explicit ConstExpr(int v) : value(v) {}
    int evaluate(int const *) const override {
        return value;
    }
    bool depends_on_bindings() const override {
        return false;
    }
};

/// Foglia: riferimento al domain_value dell'istanza (keyword "self")
/// Accede a env[ENV_SELF_INDEX]
struct SelfExpr final : Expression {
    int evaluate(int const *env) const override {
        return env[ENV_SELF_INDEX];
    }
    bool depends_on_bindings() const override {
        return false;
    }
};

/// Foglia: variabile locale risolta a runtime dall'environment tramite indice intero
/// Es: VarExpr(1) → env[1] → valore corrente dell'aggregato legato all'indice 1
struct VarExpr final : Expression {
    int index;  // Indice nell'array environment
    explicit VarExpr(int idx) : index(idx) {}
    int evaluate(int const *env) const override {
        return env[index];
    }
    bool depends_on_bindings() const override {
        return index != ENV_SELF_INDEX;
    }
};

/// Nodo intermedio: operazione binaria tra due sotto-espressioni
/// Es: BinOpExpr(ADD, VarExpr(1), ConstExpr(1)) → env[1] + 1
struct BinOpExpr final : Expression {
    BinOp op;
    std::unique_ptr<Expression> left;
    std::unique_ptr<Expression> right;

    BinOpExpr(BinOp o, std::unique_ptr<Expression> l, std::unique_ptr<Expression> r)
        : op(o), left(std::move(l)), right(std::move(r)) {}

    int evaluate(int const *env) const override {
        int lv = left->evaluate(env);
        int rv = right->evaluate(env);
        switch (op) {
            case BinOp::ADD: return lv + rv;
            case BinOp::SUB: return lv - rv;
            case BinOp::MUL: return lv * rv;
        }
        return 0; // unreachable
    }

    bool depends_on_bindings() const override {
        return left->depends_on_bindings() || right->depends_on_bindings();
    }
};

// ============================================================================
// STRUTTURE PER IL LAZY GROUNDING
// ============================================================================

/// Mappa una variabile locale al suo indice nell'environment e alla chiave aggregata.
/// Pre-calcolata in init_lazy_mode per evitare lookup stringa a runtime.
struct VarBinding {
    int env_index;      // Indice nella flat array environment (1-based, 0 è __self__)
    AggregateKey agg_key;  // Chiave dell'aggregato da cui leggere il valore
};

/// Template di una regola euristica (letto da __heuristic/N).
/// NON contiene istanziazioni concrete, solo la "forma" della regola.
///
/// Formato ASP (argomenti flessibili, ordine libero tranne il primo):
///   __heuristic(TargetPred, ...args...).
///
/// Il primo argomento è sempre il predicato target.
/// Gli argomenti successivi vengono classificati automaticamente dal parser C++:
///   - atomo semplice senza prefisso  → body positivo (es. x)
///   - prefisso __n_                  → body negativo (es. __n_c → c)
///   - __bind(var, __agg(pred))       → binding variabile → aggregato
///   - __weight(expr)                 → espressione per il peso
///   - __priority(expr)               → espressione per la priorità
///   - "true" / "false" / "sign"      → segno dell'euristica
///
/// Esempio:
///   __heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).
///   __heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(__add(s, 1)), __priority(s), true).
struct HeuristicRuleTemplate {
    std::string target_pred;                  // Primo argomento: predicato target (es. "b")
    std::vector<std::string> pos_body_preds;  // Body positivi (es. {"x"})
    std::vector<std::string> neg_body_preds;  // Body negativi (es. {"c"} da __n_c)
    std::string sign;                         // "true", "false", "sign"

    // === Fase di runtime (usato in decide, zero-allocation) ===
    // Bindings pre-calcolati: per ogni variabile, il suo indice env e la chiave aggregata
    std::vector<VarBinding> var_bindings;

    // Dimensione dell'environment per questa regola (1 + numero variabili locali)
    int env_size = 1; // Minimo 1 per __self__

    // AST per il calcolo del peso a runtime (default: costante 0)
    std::unique_ptr<Expression> weight_expr = std::make_unique<ConstExpr>(0);

    // AST per il calcolo della priorità a runtime (default: costante 0)
    std::unique_ptr<Expression> priority_expr = std::make_unique<ConstExpr>(0);

    // True se l'espressione usa almeno una variabile da __bind.
    bool weight_depends_on_bindings = false;
    bool priority_depends_on_bindings = false;
};

/// Istanza euristica creata dinamicamente durante propagate.
/// Equivale al TargetInfo della modalità statica ma generata on-demand.
struct LazyTargetInstance {
    Clingo::literal_t target_lit;                  // Literal del target (es. b(27))
    std::vector<Clingo::literal_t> neg_body_lits;  // Literal per i check negativi
    int domain_value;                               // Valore del dominio (es. 27 per x(27))
    size_t rule_idx;                                // Indice del template che l'ha generata

    // Cache opzionale: espressioni senza variabili __bind, valutate in propagate().
    int cached_weight = 0;
    int cached_priority = 0;
    bool has_cached_weight = false;
    bool has_cached_priority = false;
};

// ============================================================================
// HeuristicPropagator
// ============================================================================

class HeuristicPropagator : public Clingo::Heuristic {

private:

    struct WatchedAtomContribution {
        AggregateKey key;
        int value;
    };

    /// Info su un atomo osservato: contributi verso i vari aggregati
    struct WatchedAtomInfo {
        std::vector<WatchedAtomContribution> contributions;
    };

    /// Mappa un solver_literal ai suoi aggregate di appartenenza
    std::unordered_map<Clingo::literal_t, WatchedAtomInfo> watched_atoms_;

    // === MODALITÀ LAZY (ground-on-demand con __heuristic/N) ===

    /// Template delle regole euristiche
    std::vector<HeuristicRuleTemplate> rule_templates_;

    /// Mappa: body_literal → lista di trigger che possono
    /// essere attivati quando quel body literal diventa vero.
    struct BodyTriggerInfo {
        size_t rule_idx;                                // Indice in rule_templates_
        int domain_value;                               // Il valore X del dominio (es. 27 per x(27))
        Clingo::literal_t target_lit;                   // Literal target pre-risolto (es. b(27))
        std::vector<Clingo::literal_t> neg_body_lits;   // Literal neg body pre-risolti
    };
    std::unordered_map<Clingo::literal_t, std::vector<BodyTriggerInfo>> body_triggers_;

    /// Target euristici istanziati dinamicamente (generati in propagate).
    /// Chiave: body_literal che ha triggerato l'istanziazione.
    /// Ogni body_literal può generare più istanze (una per ogni template che matcha).
    std::unordered_map<Clingo::literal_t, std::vector<LazyTargetInstance>> lazy_targets_;

    /// Set dei body literal attivi (per iterazione efficiente in decide)
    std::vector<Clingo::literal_t> active_body_lits_;

    /// Posizione di ciascun body active nel vettore (per rimozione O(1)).
    std::unordered_map<Clingo::literal_t, size_t> active_body_pos_;



    // === CONDIVISO ===

    /// Mappa gli aggregate key ai loro stati dinamici (polimorfici)
    std::unordered_map<AggregateKey, std::unique_ptr<AggregateState>, AggregateKeyHash> aggregate_states_;

    // === Buffer pre-allocato per decide() (zero-allocation hot path) ===

    /// Flat array riutilizzato per l'environment delle espressioni in decide().
    /// Dimensionato al massimo env_size tra tutti i template in init_lazy_mode().
    std::vector<int> env_buffer_;

    using PredLitMap = std::unordered_map<std::string, std::unordered_map<int, Clingo::literal_t>>;

    struct LazyInitInfo {
        std::unordered_set<std::string> body_preds;
        std::unordered_set<std::string> target_preds;
        std::unordered_set<std::string> neg_body_preds;
        std::unordered_set<std::string> aggregate_preds;
        int max_env_size = 1;
    };

    struct TemplateParseState {
        int next_var_index = 1;
        std::unordered_map<std::string, int> var_index_map;
        std::unique_ptr<Expression> legacy_weight_expr;
        std::unique_ptr<Clingo::Symbol> weight_term;
        std::unique_ptr<Clingo::Symbol> priority_term;
    };

    // === Metodi helper privati ===
    void init_lazy_mode(Clingo::PropagateInit &init);
    void parse_lazy_templates(Clingo::SymbolicAtoms const &atoms, LazyInitInfo &info);
    void parse_lazy_template_symbol(Clingo::Symbol const &symbol, LazyInitInfo &info);
    bool try_parse_bind_argument(Clingo::Symbol const &arg,
                                 HeuristicRuleTemplate &tmpl,
                                 LazyInitInfo &info,
                                 TemplateParseState &state);
    bool try_parse_weight_argument(Clingo::Symbol const &arg,
                                   HeuristicRuleTemplate &tmpl,
                                   TemplateParseState &state);
    bool try_parse_priority_argument(Clingo::Symbol const &arg,
                                     HeuristicRuleTemplate &tmpl,
                                     TemplateParseState &state);
    bool try_parse_simple_argument(Clingo::Symbol const &arg,
                                   HeuristicRuleTemplate &tmpl,
                                   LazyInitInfo &info,
                                   TemplateParseState &state);
    void parse_template_argument(Clingo::Symbol const &arg,
                                HeuristicRuleTemplate &tmpl,
                                LazyInitInfo &info,
                                TemplateParseState &state);
    void finalize_lazy_template(HeuristicRuleTemplate &tmpl,
                                LazyInitInfo &info,
                                TemplateParseState &state);
    PredLitMap build_pred_lit_map(Clingo::PropagateInit &init,
                                  Clingo::SymbolicAtoms const &atoms,
                                  LazyInitInfo const &info);
    void build_body_triggers(Clingo::PropagateInit &init, PredLitMap const &pred_lit_map);
    void register_aggregate_watches(Clingo::PropagateInit &init, Clingo::SymbolicAtoms const &atoms);
    void remove_active_body_lit(Clingo::literal_t body_lit) noexcept;

    /// Parsing ricorsivo di un termine Clingo in un AST Expression.
    /// Riconosce costanti, "self", variabili (nomi presenti in var_index_map),
    /// e operazioni binarie (__add, __sub, __mul).
    /// var_index_map mappa nomi di variabili ai loro indici nell'environment.
    static std::unique_ptr<Expression> parse_expression(
        Clingo::Symbol const &sym,
        std::unordered_map<std::string, int> const &var_index_map,
        bool &ok,
        std::string &error_message);

public:
    ~HeuristicPropagator() override = default;

    void init(Clingo::PropagateInit &init) override;
    void propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) override;
    void undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept override;
    Clingo::literal_t decide(Clingo::id_t thread_id, Clingo::Assignment const &assignment, Clingo::literal_t fallback) override;
};