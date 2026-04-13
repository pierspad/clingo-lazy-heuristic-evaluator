Per "chiudere il cerchio" del tuo lavoro di tesi e renderlo impeccabile, ci sono diverse migliorie e semplificazioni che puoi apportare. Alcune riguardano la **pulizia del codice**, altre l'**ottimizzazione delle performance** e altre ancora la **formalizzazione teorica** (fondamentale per una tesi).

Ecco una roadmap per finalizzare il progetto:

---

## 1. Pulizia e Semplificazione del Codice

### Unificare le passate di parsing
Attualmente `init_lazy_mode` fa due passate sui fatti `__heuristic`. Puoi unificarle pre-inizializzando il `VarBinding` non appena trovi un `__bind`.
* **Vantaggio:** Codice più corto e meno dispersivo.
* **Suggerimento:** Invece di `std::unordered_map<std::string, AggregateKey> local_vars`, usa direttamente una mappa che associa il nome della variabile all'indice finale nell'environment.

### Utilizzo di `std::max` e costruttori predefiniti
Come abbiamo visto, puoi rendere il codice più "C++ moderno":
```cpp
// Invece di if espliciti
tmpl.env_size = next_var_index;
max_env_size = std::max(max_env_size, tmpl.env_size);

// Usa i valori di default nel template per evitare i blocchi "if (!tmpl.weight_expr)"
struct HeuristicRuleTemplate {
    std::unique_ptr<Expression> weight_expr = std::make_unique<ConstExpr>(0);
    // ...
};
```

### Gestione degli errori (Robustezza)
Aggiungi dei messaggi di errore (usando `std::cerr` o le eccezioni di Clingo) se il parsing dell'espressione fallisce (es. una variabile usata in `__weight` che non è stata definita in un `__bind`). Questo trasforma il tuo prototipo in uno strumento "professionale".

---

## 2. Ottimizzazioni del "Hot Path" (`decide`)

Il metodo `decide` è quello che corre di più. Possiamo renderlo ancora più veloce:

### Pre-valutazione delle espressioni statiche
Se un'espressione `__weight` o `__priority` non contiene variabili (è solo una costante o un valore `self`), puoi valutarla una volta sola in `propagate` (quando crei l'istanza) e memorizzare il risultato nell'oggetto `LazyTargetInstance`.
* **Perché:** In `decide`, non dovrai più chiamare `evaluate()` per quelle istanze, ma leggerai un intero già pronto.

### Ottimizzazione di `active_body_lits_`
Attualmente usi un `std::vector` e fai `std::find` in `undo`. Se il numero di euristiche attive è molto alto, questo è $O(n)$.
* **Miglioria:** Se necessario, potresti usare un `std::set` o aggiungere un flag booleano nel `BodyTriggerInfo` per sapere se è già attivo, evitando la ricerca lineare.

---

## 4. Formalizzazione Scientifica (Per il testo della tesi) migliora la spiegazione, ormai vetusta, in riassunto_esecuzione.lp

Per "wrappare" la tesi, assicurati di descrivere bene questi tre punti:

### Analisi della Complessità
Prepara una tabella che confronti la complessità del grounding standard vs lazy.
* **Standard:** $O(N^k)$ dove $k$ è il numero di variabili nel corpo dell'euristica.
* **Lazy:** $O(T + E)$ dove $T$ è il numero di template e $E$ è il costo di valutazione dell'AST.

### Dimostrazione della Correttezza
Spiega brevemente perché `undo()` garantisce che il solver non "impazzisca" dopo un conflitto. La gestione del multiset implicito per `min/max` è un ottimo punto tecnico da valorizzare:
> *"Per min/max non basta l'inversa aritmetica; manteniamo un conteggio delle occorrenze per recuperare l'estremo precedente in $O(\log M)$ senza ricalcolo totale."*

### Discussione dei Risultati (Benchmark)
Nel capitolo dei risultati, commenta i grafici prodotti da `graphs.py`. 
* Sottolinea il punto in cui la RAM del "Clingo Standard" esplode (N=100+).
* Evidenzia che il "Solving Time" è quasi identico, dimostrando che il tuo propagatore non introduce un overhead significativo.

---

## Esempio di tabella riepilogativa per la tesi

| Caratteristica | Grounding Standard | Lazy Heuristic (Tuo Lavoro) |
| :--- | :--- | :--- |
| **Dimensione Programma** | Esplosione combinatoria ($O(N^k)$) | Lineare rispetto ai template ($O(T)$) |
| **Utilizzo RAM** | Molto alto (satura per $N$ grandi) | Basso e costante rispetto a $N$ |
| **Flessibilità** | Statica (valori fissati al grounding) | Dinamica (valutata sull'assegnamento parziale) |
| **Complessità Solving** | $O(1)$ (lookup tabella) | $O(E)$ (valutazione AST) |

