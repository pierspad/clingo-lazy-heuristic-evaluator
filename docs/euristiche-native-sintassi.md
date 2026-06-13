# Euristiche lazy — sintassi del propagatore **native** (`__heuristic`)

Guida di riferimento per scrivere a mano le euristiche dell'**approccio A** (propagatore
incrementale nativo), quello compilato nel binario **`clingo-native`**.

L'approccio A si attiva quando nel programma ground compaiono **fatti `__heuristic(...)`**.
Il propagatore li legge in `init()`, costruisce a runtime i "candidati" per ogni atomo
target ground, e durante la ricerca sceglie su quale letterale decidere
(`decide()`), aggiornando gli stati in modo incrementale in `propagate()`/`undo()`.

> Per far sì che le decisioni del propagatore guidino davvero la ricerca, lancia clingo con
> **`--heuristic=Domain`** (è esattamente ciò che fa `benchmark_runner.py`). Senza quel flag
> il programma resta corretto — stessi answer set — ma l'ordine delle decisioni non è
> guidato dall'euristica.

La grammatica qui descritta è quella effettivamente implementata in
`libclingo/src/heuristic_parser.cc` (funzione `parse_lazy_heuristic_templates`): se scrivi
qualcosa fuori da queste regole, il parser lancia un'eccezione `Sintassi euristica malformata`.

---

## 1. Forma generale

```prolog
__heuristic(ARG_1, ARG_2, ..., ARG_k).
```

Un fatto `__heuristic/k` descrive **una regola euristica**. Gli argomenti sono *keyword
posizionali liberi*: l'ordine non conta, conta il **nome del funtore** di ciascun argomento.
Ogni `ARG_i` è uno dei costrutti delle sezioni seguenti.

Puoi avere **più fatti `__heuristic`** nello stesso programma: ognuno genera una regola
indipendente, e le regole possono insistere sullo stesso target (vedi §8, risoluzione per
priorità locale).

Vincoli globali:

- **`__target(pred)` è obbligatorio** ed è ammesso **una sola volta** per regola. Senza,
  errore `__heuristic richiede un argomento __target(pred)`.
- Ogni nome di variabile (introdotto da `__bind`, `__bind_arg`, `__bind_target_arg`) deve
  essere **definito una sola volta** nella regola; altrimenti errore `variabile '...'
  definita piu' volte`.
- Ogni argomento deve essere un **funtore** (mai un numero o una stringa nudi al primo
  livello): un argomento non-funtore dà `argomento non valido in __heuristic`.

---

## 2. `__target(pred)` — il predicato bersaglio (obbligatorio)

```prolog
__target(choose)
```

- `pred` deve essere un **funtore nullario** (solo il nome del predicato, senza argomenti):
  `__target(choose)`, **non** `__target(choose(X))`.
- La regola si applica a **tutti gli atomi ground** di quel predicato presenti nel programma
  (es. `choose(1)`, `choose(3,1)`, ...). Per ognuno il propagatore crea un *candidato*.
- L'**arità** del target è dedotta dagli atomi ground, non dichiarata qui.

Il valore speciale **`self`** (vedi §6) vale **il primo argomento** del target ground
(indice 0). Per `choose(3)` → `self = 3`; per `choose(3,1)` → `self = 3`.

---

## 3. Corpo positivo — quando il candidato è "attivabile"

Il corpo positivo dice **a quali atomi target** la regola si applica e **come legarli** ad
altri atomi del programma. Due forme.

### 3a. Forma implicita: nome di predicato nudo

```prolog
__heuristic(__target(choose), dom, __weight(self), __priority(1), __modifier(true)).
```

`dom` (funtore nullario, non riservato) è un **predicato di corpo positivo con mapping
implicito posizionale**: per il target `choose(T0,...,Tn)` deve esistere un atomo ground
`dom(T0,...,Tn)` con **la stessa tupla identica** (stessa arità, stessi valori). È il pattern
classico "applica l'euristica a `choose(X)` solo se `dom(X)` esiste".

### 3b. Forma esplicita: `__body(pred, __match(...), __bind_arg(...))`

```prolog
__body(body, __match(0, 0), __bind_arg(w, 1))
```

Da usare quando il predicato di corpo ha **arità diversa** dal target, o quando vuoi
**estrarre un valore** dal corpo per usarlo nel peso/priorità.

- Primo argomento: il **nome predicato** (funtore nullario), qui `body`.
- **`__match(src_idx, tgt_idx)`** — *join*: l'argomento in posizione `src_idx` dell'atomo di
  corpo deve essere uguale all'argomento in posizione `tgt_idx` del target. Indici **0-based**.
  Ne serve **almeno uno** (`__body richiede almeno un __match`).
- **`__bind_arg(var, src_idx)`** — lega la variabile `var` al valore dell'argomento in
  posizione `src_idx` dell'atomo di corpo, rendendola usabile in `__weight`/`__priority`.
- Indici negativi → errore. `var` deve essere un funtore nullario (un identificatore).

Esempio completo (verificato dai test): con `score(1,10) score(2,5) score(3,7)` e
`body(X,W) :- dom(X), score(X,W).`

```prolog
__heuristic(__target(choose), __body(body, __match(0, 0), __bind_arg(w, 1)),
            __weight(w), __priority(1), __modifier(true)).
```

→ per ogni `choose(X)`, `w` = secondo argomento di `body(X,_)`; viene scelto `choose(1)`
(peso 10, il massimo).

---

## 4. Corpo negativo — `__n_pred`

Un funtore **nullario il cui nome inizia per `__n_`** è un letterale di corpo **negato**:
`__n_c` significa "**not** `c`". Il predicato (`c`) viene matchato **sulla stessa tupla del
target**.

```prolog
__heuristic(__target(choose), dom, __n_c, __weight(self), __priority(1)).
```

→ applica l'euristica a `choose(X)` solo se `dom(X)` e **non** `c(X)`. La nozione di "non"
dipende dalla **semantica** (§9): in `clingo` il letterale negato dev'essere *falso*; in
`alpha` basta che **non sia vero** (falso oppure ancora indeciso).

---

## 5. Aggregati incrementali — `__bind(var, __agg(pred, idx?, __filter...))`

Lega una variabile al **valore di un aggregato** calcolato e mantenuto **incrementalmente**
dal propagatore (scommit/rollback su `propagate`/`undo`).

```prolog
__bind(s, __sum(source, 1, __filter(0, 0)))
```

- `var` (`s`): funtore nullario, la variabile legata (usabile in peso/priorità).
- Operatore aggregato: **`__sum`, `__count`, `__min`, `__max`** (qualsiasi altro → errore
  `operatore aggregato sconosciuto`).
- Dentro l'operatore: `__agg(pred, idx?, filtri...)`:
  - `pred` — predicato sorgente (funtore nullario), obbligatorio.
  - `idx` (numerico, **opzionale**) — **indice 0-based dell'argomento aggregato** (il
    "valore"). Per `__count` è irrilevante. Indice negativo → errore.
  - zero o più **`__filter(src_idx, tgt_idx, offset?)`** — vincolano la sorgente al target:
    l'argomento `src_idx` della sorgente deve valere `target[tgt_idx] + offset` (offset
    intero opzionale, default 0). Così l'aggregato è **specifico per ciascun target**.

Esempio (verificato): con `source(1,5) source(2,9)` e target `choose(X)`,

```prolog
__heuristic(__target(choose), dom,
            __bind(s, __sum(source, 1, __filter(0, 0))),
            __weight(s), __priority(1), __modifier(true)).
```

→ `s` = somma del **2º argomento** di `source` (indice 1) sui soli atomi con `source[0] = X`
(il filtro lega l'arg 0 della sorgente all'arg 0 del target). `choose(2)` ottiene `s=9` e
viene scelto.

> Semantica dell'aggregato (vedi §9): con `clingo` il candidato si attiva **solo quando tutte
> le sorgenti dell'aggregato sono determinate**; con `alpha` si usa il valore corrente
> (parziale) dell'aggregato, e una chiave runtime mancante vale 0.

---

## 6. Peso — `__weight(expr)` (o `self`)

Il **peso** (bias) è il valore numerico associato alla decisione. Default `0` se assente.

- `__weight(EXPR)` dove `EXPR` è un'**espressione aritmetica** (§7).
- Forma abbreviata: il funtore nullario **`self`** scritto come argomento di primo livello
  equivale a `__weight(self)`.
- `__weight` duplicato (o `self` + `__weight`) → errore `peso/__weight duplicato`.

---

## 7. Espressioni aritmetiche (peso e priorità)

Una `EXPR` in `__weight`/`__priority` è ricorsivamente uno di:

| Forma | Significato |
|---|---|
| numero intero (es. `10`, `-3`) | costante |
| `self` | primo argomento del target ground (indice 0) |
| una **variabile legata** | valore da `__bind` / `__bind_arg` / `__bind_target_arg` |
| `__add(E1, E2)` | `E1 + E2` |
| `__sub(E1, E2)` | `E1 - E2` |
| `__mul(E1, E2)` | `E1 * E2` |

Esempio: `__weight(__add(__mul(self, 10), w))` = `self*10 + w`.

Vincoli: gli operatori `__add/__sub/__mul` richiedono **esattamente due argomenti**; una
variabile non definita con un `__bind*` dà errore (`variabile '...' usata in __weight ma non
definita`); operatori sconosciuti → errore.

---

## 8. Priorità — `__priority(expr)`

```prolog
__priority(1)
```

Stessa grammatica del peso (§7). Default `0`. **Deve essere ≥ 0 a runtime** (priorità locale
negativa → eccezione a tempo di risoluzione).

Ruolo nella decisione (logica di `decide()`/`refresh_target`):

1. **Risoluzione locale (stesso target).** Quando più regole/candidati toccano lo stesso
   atomo target, per ciascun *modificatore* (livello, segno) vince il contributo con
   **priorità locale più alta**; a parità di priorità, vince il `candidate_id` minore (la
   regola dichiarata prima). Vedi `update_best_by_local_priority`.
2. **Rank globale tra target diversi.** Tra atomi target ancora liberi, il propagatore sceglie
   per **priorità di decisione decrescente**, poi **peso decrescente**, poi tie-break
   deterministico (stringa del target, poi letterale). Vedi l'insieme ordinato
   `active_decision_ranks_`.

Esempio (verificato): due regole sullo stesso target,

```prolog
__heuristic(__target(choose), __body(mark, __match(0, 0)),
            __weight(1), __priority(100), __modifier(true)).
__heuristic(__target(choose), dom,
            __weight(self), __priority(0), __modifier(true)).
```

con `dom(1..2)` e `mark(1)` → risultato `choose(2)`.

---

## 9. Modificatore — `__modifier(m)` (o `m` nudo)

```prolog
__modifier(true)
```

Valori ammessi: **`level`, `sign`, `true`, `false`, `init`, `factor`**. Default **`true`**.
Forma abbreviata: il nome del modificatore scritto come argomento di primo livello nudo (es.
`true`) equivale a `__modifier(true)`.

Semantica (da `apply_effect_to_target_state`):

| Modificatore | Effetto |
|---|---|
| `level` | imposta il **livello/peso** del target al valore di `__weight` (alla priorità locale data) |
| `sign`  | imposta solo il **segno**: peso `> 0` → preferisci *vero*, `< 0` → *falso*, `0` → nessuna preferenza |
| `true`  | come `level` **e** segno *vero* (preferisci assegnare il target a vero) |
| `false` | come `level` **e** segno *falso* |
| `init` / `factor` | **non supportati** dal propagatore: errore a runtime `init/factor non supportati` |

`__modifier` duplicato → errore.

---

## 10. Semantica — `__semantics(alpha|clingo)`

```prolog
__semantics(clingo)
```

Default: **`clingo`** (è il default di `HeuristicRuleTemplate`). `__semantics(alpha)` passa
ad Alpha. Influenza due cose:

- **Negazione** (`__n_pred`, §4): con `clingo` il letterale negato dev'essere **falso**; con
  `alpha` basta che **non sia vero** (falso o ancora libero).
- **Aggregati** (§5): con `clingo` il candidato si attiva **solo a sorgenti completamente
  determinate**; con `alpha` si usa il valore parziale corrente. Inoltre, con `alpha`, i
  candidati con modificatore `level/true/false` sono ordinati come **rank globale** per
  priorità poi peso (vedi `refresh_target`, ramo `best_alpha_effect`).

> Promemoria: per le **stringhe** `heuristic("... alpha_not ... clingo_not ...")` la semantica
> si deduce dalla sintassi — ma quello è l'approccio **Prolog** (`clingo-prolog`), vedi l'altra
> guida. Qui, con `__heuristic`, la semantica è esplicita con `__semantics`.

---

## 11. `self` e gli indici, in breve

- **`self`** = `target[0]` (primo argomento del target ground).
- Tutti gli indici (`__match`, `__filter`, `__bind_arg`, `__bind_target_arg`, l'`idx` di
  `__bind`) sono **0-based** e **non negativi**.
- **`__bind_target_arg(var, i)`** lega `var` all'argomento `i` del **target** (utile per i
  target multi-argomento: `self` copre solo l'indice 0).

Esempio (verificato): target `choose(X,Y)` con `dom(1,100) dom(3,1)`,

```prolog
__heuristic(__target(choose), dom, __bind_target_arg(y, 1),
            __weight(y), __priority(1), __modifier(true)).
```

→ `y` = secondo argomento del target; viene scelto `choose(1,100)` (`y=100`, massimo).

---

## 12. Regole, vincoli ed errori (riassunto del validatore)

Il parser rifiuta (con `Sintassi euristica malformata: ...`):

- `__heuristic` senza argomenti, o senza `__target`.
- `__target` non `__target(pred)` con `pred` nullario, oppure target duplicato.
- variabile (`__bind`/`__bind_arg`/`__bind_target_arg`) **definita più volte**.
- `__bind` non nella forma `__bind(var, __agg(pred, idx?, filtri...))`; operatore aggregato
  non in `{__sum,__count,__min,__max}`; indice aggregato negativo o non numerico.
- `__filter` con meno di 2 / più di 3 argomenti, indici non numerici, o indici negativi.
- `__match` non con due indici numerici non negativi.
- `__body` senza predicato nullario iniziale, o **senza alcun `__match`**, o con argomenti
  annidati diversi da `__match`/`__bind_arg`.
- `__weight`/`__priority`/`__modifier`/`__semantics` duplicati o con arità diversa da 1.
- `__modifier`/`__semantics` con valore fuori dall'elenco ammesso.
- espressione aritmetica con variabile non legata, operatore sconosciuto, o arità ≠ 2.

A runtime: priorità locale negativa, o modificatore `init`/`factor`, sollevano eccezione.

---

## 13. Esempi completi e funzionanti

**Massimizza il valore scelto** (dai test, `--heuristic=Domain -n 1`):

```prolog
dom(1..3).
1 { choose(X) : dom(X) } 1.
__heuristic(__target(choose), dom, __weight(self), __priority(1), __modifier(true)).
#show choose/1.
% -> choose(3)
```

**Corner case (UNSAT resta UNSAT, SAT resta SAT):** l'euristica non cambia mai l'insieme
delle soluzioni, solo l'ordine di esplorazione. Con `dom(1). { choose(X) } :- dom(X). :- not
choose(1). :- choose(1).` il programma è UNSAT con o senza `__heuristic`.

**Esempio "BSP-like" nativo** (equivalente all'encoding Prolog `BSP_la.lp`, qui in sintassi
nativa). Dato `x(1..n)` e i guess `b/1`, `c/1`:

```prolog
__heuristic(__target(b), x, __bind(s, __sum(c)), __n_c,
            __weight(__add(__mul(s, 2), self)), __priority(0), __semantics(alpha), __modifier(true)).
__heuristic(__target(c), x, __bind(s, __sum(b)), __n_b,
            __weight(__add(__mul(s, 2), self)), __priority(0), __semantics(alpha), __modifier(true)).
```

(letto: per ogni `b(X)` con `x(X)` e non `c(X)`, peso = `2*Σb del c-set + X`; simmetrico per
`c`). Adatta nomi/indici al tuo encoding reale prima dell'uso e verifica con
`--heuristic=Domain` confrontando l'ottimo/gli answer set rispetto alla variante senza
euristica.

---

## 14. Riferimento rapido

| Costrutto | Sintassi | Note |
|---|---|---|
| Target | `__target(pred)` | obbligatorio, 1 volta, `pred` nullario |
| Corpo implicito | `pred` | tupla del corpo = tupla del target |
| Corpo esplicito | `__body(pred, __match(s,t), __bind_arg(v,s2))` | ≥1 `__match` |
| Corpo negato | `__n_pred` | matchato sulla tupla del target |
| Aggregato | `__bind(v, __sum/__count/__min/__max(pred, idx?, __filter(s,t,off?)...))` | incrementale |
| Arg. target → var | `__bind_target_arg(v, i)` | i = indice target |
| Peso | `__weight(EXPR)` o `self` | default 0 |
| Priorità | `__priority(EXPR)` | default 0, ≥0 a runtime |
| Modificatore | `__modifier(level\|sign\|true\|false)` o nudo | default `true`; `init/factor` non supportati |
| Semantica | `__semantics(alpha\|clingo)` | default `clingo` |
| Espressioni | `self`, numero, var, `__add/__sub/__mul(E,E)` | — |

Flag d'esecuzione utile: **`--heuristic=Domain`** per far guidare le decisioni dall'euristica.
