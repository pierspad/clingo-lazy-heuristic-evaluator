# Euristiche lazy — sintassi del propagatore **native** (`__heuristic`)

Guida di riferimento per scrivere a mano le euristiche del propagatore **`clingo-native`**.

L'approccio si attiva quando nel programma ground compaiono **fatti `__heuristic(...)`**.
Il propagatore li legge in `init()`, costruisce a runtime i "candidati" per ogni atomo
target ground, e durante la ricerca sceglie su quale letterale decidere
(`decide()`), aggiornando gli stati in modo incrementale in `propagate()`/`undo()`.

> Tutte le run (test C++ e runscript del benchmark) passano il flag clingo
> **`--heuristic=Domain`**. L'euristica non cambia mai l'insieme delle risposte, solo
> l'ordine in cui lo spazio di ricerca viene esplorato.

---

## 1. Forma generale

```prolog
__heuristic(ARG_1, ARG_2, ..., ARG_k).
```

Ogni `__heuristic/k` descrive **una regola euristica**.L'ordine degli ARGS non conta e conta solo il nome di ciascun argomento.
Ogni `ARG_i` è uno tra:


#### 2. `__target(pred)` (obbligatorio)

```prolog
__target(choose)
```

- `pred` deve essere senza argomenti, solo il nome del predicato
  `__target(choose)`, **non** `__target(choose(X))`.
- Per ognuno di **tutti gli atomi ground** di quel predicato presenti nel programma il propagatore crea un *candidato*.

Il valore speciale **`self`** vale come **il primo argomento** del target ground
(indice 0). Per `choose(3)` -> `self = 3`; per `choose(3,1)` -> `self = 3`.

---

#### 3. Corpo positivo — quando il candidato è "attivabile"

Il corpo positivo dice **a quali atomi target** la regola si applica

### 3a. Forma implicita

```prolog
__heuristic(__target(choose), dom, __weight(self), __priority(1), __modifier(true)).
```

`dom` è un predicato di corpo positivo: per il target `choose(T0,...,Tn)` deve esistere un atomo ground
`dom(T0,...,Tn)` con **la stessa tupla identica** (stessa arità, stessi valori). 

### 3b. Forma esplicita: `__body(pred, __match(...), __bind_arg(...))`

```prolog
__body(body, __match(0, 0), __bind_arg(w, 1))
```

Da usare quando il predicato di corpo ha **arità diversa** dal target, o quando vuoi
**estrarre un valore** dal corpo per usarlo nel peso/priorità.

- Primo argomento: il **nome predicato**, qui `body`.
- **`__match(src_idx, tgt_idx)`** — *joina* l'argomento in posizione `src_idx` dell'atomo di
  corpo con l'argomento in posizione `tgt_idx` del target.
  `__body richiede almeno un __match`.
- **`__bind_arg(var, src_idx)`** — lega la variabile `var` al valore dell'argomento in
  posizione `src_idx` dell'atomo di corpo, rendendola usabile in `__weight`/`__priority`.

Esempio completo con `score(1,10) score(2,5) score(3,7)` e
`body(X,W) :- dom(X), score(X,W).`

```prolog
__heuristic(__target(choose), __body(body, __match(0, 0), __bind_arg(w, 1)),
            __weight(w), __priority(1), __modifier(true)).
```

-> per ogni `choose(X)`, `w` = secondo argomento di `body(X,_)`; viene scelto `choose(1)`.

---

## 4. Corpo negativo — `__n_pred`

Un argomento il cui nome inizia per `__n_` è un letterale di corpo **negato**:
`__n_c` significa "**not** `c`". Il predicato (`c`) viene matchato **sulla stessa tupla del
target**.

```prolog
__heuristic(__target(choose), dom, __n_c, __weight(self), __priority(1)).
```

-> applica l'euristica a `choose(X)` solo se `dom(X)` e **not** `c(X)`. 
il "not" dipende dalla **semantica**: in `clingo` il letterale negato dev'essere *falso*; in
`alpha` basta che **non sia vero** (falso oppure ancora indeciso).

---

## 5. Aggregati incrementali — `__bind(var, __agg(pred, idx?, __filter...))`

Lega una variabile al **valore di un aggregato** calcolato e mantenuto **incrementalmente**
dal propagatore (scommit/rollback su `propagate`/`undo`).

```prolog
__bind(s, __sum(source, 1, __filter(0, 0)))
```

- `var` (`s`): la variabile legata (usabile in peso/priorità).
- Operatore aggregato: **`__sum`, `__count`, `__min`, `__max`**
- Dentro l'operatore: `__agg(pred, idx?, filtri...)`:
  - `pred` — predicato sorgente (obbligatorio).
  - `idx`  — **indice 0-based dell'argomento aggregato** (numerico, **opzionale**)
  - zero o più **`__filter(src_idx, tgt_idx, offset?)`** — vincolano la sorgente al target:
    l'argomento `src_idx` della sorgente deve valere `target[tgt_idx] + offset` 

Esempio con `source(1,5) source(2,9)` e target `choose(X)`,

```prolog
__heuristic(__target(choose), dom,
            __bind(s, __sum(source, 1, __filter(0, 0))),
            __weight(s), __priority(1), __modifier(true)).
```

-> `s` = somma del **2º argomento** di `source` (indice 1) sui soli atomi con `source[0] = X`
`choose(2)` ottiene `s=9` e viene scelto.

> Semantica dell'aggregato con `clingo` il candidato si attiva **solo quando tutte
> le sorgenti dell'aggregato sono determinate**; con `alpha` si usa il valore corrente
> (parziale) dell'aggregato, e una chiave runtime mancante vale 0.

---

## 6. Peso — `__weight(expr)` (o `self`)

Il **peso** è il valore numerico associato alla decisione. Default `0` se assente.

- `__weight(EXPR)` dove `EXPR` è un'**espressione aritmetica**.
- Forma abbreviata: **`self`** scritto come argomento di primo livello
  equivale a `__weight(self)`.
- `__weight` duplicato (o `self` + `__weight`) -> errore `peso/__weight duplicato`.

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

---

## 8. Priorità — `__priority(expr)`

`__priority(EXPR)` è un'espressione aritmetica come il peso (§7): può usare `self` e le
variabili legate. Default `0`; un valore **negativo** a runtime solleva eccezione.

La priorità agisce in **due punti diversi**.

**a) Fra regole sullo stesso target.** Se più `__heuristic` producono un candidato per lo
stesso atomo target, vince quella con priorità **maggiore**; a parità, la regola **dichiarata
prima**. Con semantica `clingo` la risoluzione è **per slot**: il livello (il peso) e il segno
vengono assegnati indipendentemente, quindi una regola `sign` ad alta priorità e una regola
`level` a priorità più bassa possono convivere sullo stesso target.

**b) Fra target diversi.** Il propagatore tiene una coda dei target ancora liberi ordinata per
**(priorità, peso, letterale)** decrescente, e `decide()` prende il primo. Qui però la priorità
entra **solo con `__semantics(alpha)`**: con `clingo`, risolto il punto (a), la priorità locale
viene **azzerata** e l'ordine globale dipende **solo dal peso**.

Un target entra in coda solo se **priorità > 0 oppure peso > 0**: con semantica `clingo` (dove
la priorità globale è sempre 0) un candidato con peso ≤ 0 non viene mai scelto dal propagatore.

Esempio con `dom(1..2)` e `mark(1)`:

```prolog
__heuristic(__target(choose), __body(mark, __match(0,0)), __weight(1), __priority(100), __modifier(true)).
__heuristic(__target(choose), dom, __weight(self), __priority(0), __modifier(true)).
```

-> `choose(1)` prende peso `1` (la priorità 100 vince sulla seconda regola), `choose(2)` prende
peso `2`; poi, essendo semantica `clingo`, il confronto finale è sui pesi e viene scelto
`choose(2)`. Aggiungendo `__semantics(alpha)` a entrambe le regole, `choose(1)` si porta dietro
la priorità 100 anche nel rank globale e viene scelto lui.

---

## 9. Modificatore — `__modifier(m)` (o `m` nudo)

```prolog
__modifier(true)
```

Valori ammessi: **`level`, `sign`, `true`, `false`, `init`, `factor`**. Default **`true`**.

Semantica:

| Modificatore | Effetto |
|---|---|
| `level` | imposta il **livello/peso** del target al valore di `__weight` (alla priorità locale data) |
| `sign`  | imposta solo il **segno**: peso `> 0` -> preferisci *vero*, `< 0` -> *falso*, `0` -> nessuna preferenza |
| `true`  | come `level` **e** segno *vero* (preferisci assegnare il target a vero) |
| `false` | come `level` **e** segno *falso* |
| `init` / `factor` | **non supportati** dal propagatore: errore a runtime `init/factor non supportati` |


---

## 10. Semantica — `__semantics(alpha|clingo)`

```prolog
__semantics(clingo)
```

Default: **`clingo`**.
Influenza tre cose:

- **Negazione** (`__n_pred`): con `clingo` il letterale negato dev'essere **falso**; con
  `alpha` basta che **non sia vero** (falso o ancora libero).
- **Aggregati**: con `clingo` il candidato si attiva **solo a sorgenti completamente
  determinate**; con `alpha` si usa il valore parziale corrente.
- **Priorità** (§8): con `alpha` la priorità locale diventa anche la priorità **globale** del
  target nella coda delle decisioni; con `clingo` serve solo a scegliere fra regole dello
  stesso target e poi viene azzerata, quindi i target si ordinano solo per peso.

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

-> `y` = secondo argomento del target; viene scelto `choose(1,100)` (`y=100`, massimo).

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

**Corner case**: l'euristica non cambia mai l'insieme delle soluzioni, solo l'ordine di esplorazione. Con 
```prolog
dom(1). 
{ choose(X) } :- dom(X). 
:- not choose(1). 
:- choose(1).
``` 
il programma è UNSAT con o senza `__heuristic`.

**Esempio "BSP-like" nativo**: Dato `x(1..n)` e i guess `b/1`, `c/1`:

```prolog
__heuristic(__target(b), x, __bind(s, __sum(c)), __n_c,
            __weight(__add(__mul(s, 2), self)), __priority(0), __semantics(alpha), __modifier(true)).
__heuristic(__target(c), x, __bind(s, __sum(b)), __n_b,
            __weight(__add(__mul(s, 2), self)), __priority(0), __semantics(alpha), __modifier(true)).
```

---

## 14. Riferimento rapido

| Costrutto | Sintassi | Note |
|---|---|---|
| Target | `__target(pred)` | obbligatorio, 1 volta, `pred` nullario |
| Corpo implicito | `pred` | tupla del corpo = tupla del target |
| Corpo esplicito | `__body(pred, __match(s,t), __bind_arg(v,s2))` | ≥1 `__match` |
| Corpo negato | `__n_pred` | matchato sulla tupla del target |
| Aggregato | `__bind(v, __sum/__count/__min/__max(pred, idx?, __filter(s,t,off?)...))` | incrementale |
| Arg. target -> var | `__bind_target_arg(v, i)` | i = indice target |
| Peso | `__weight(EXPR)` o `self` | default 0 |
| Priorità | `__priority(EXPR)` | default 0, ≥0 a runtime; rank globale solo con `alpha` |
| Modificatore | `__modifier(level\|sign\|true\|false)` o nudo | default `true`; `init/factor` non supportati |
| Semantica | `__semantics(alpha\|clingo)` | default `clingo` |
| Espressioni | `self`, numero, var, `__add/__sub/__mul(E,E)` | — |

Flag d'esecuzione utile: **`--heuristic=Domain`** per far guidare le decisioni dall'euristica.
