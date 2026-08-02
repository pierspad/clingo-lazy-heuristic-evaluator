# Euristiche lazy — sintassi **Prolog** (`heuristic("...")`)

Guida di riferimento per scrivere a mano le euristiche dell'**approccio B**, quello compilato
nel binario **`clingo-prolog`**.

L'approccio B si attiva quando nel programma ground compaiono **fatti stringa**
`heuristic("...")` (o l'alias legacy `prolog_heuristic("...")`). Ogni stringa contiene **una
regola** la cui testa è `heuristic(Target, Weight, Priority, Modifier)`. A ogni decisione il
propagatore valuta le regole sullo stato corrente della ricerca e sceglie il target migliore.

> Come l'altro approccio, tutte le run passano il flag clingo **`--heuristic=Domain`**.
> L'euristica non cambia mai l'insieme delle risposte, solo l'ordine di esplorazione.

## Due backend di valutazione (stessa sintassi-contenitore, due stili di corpo)

| Backend | Quando | Stile del corpo regola |
|---|---|---|
| **SWI-Prolog** | variabile d'ambiente `LAZY_HEURISTIC_BACKEND=prolog` | Prolog vero: `holds/1`, `aggregate_all/3`, `is/2`, `target_available/1`, `n/1` |
| **clingo ausiliario** (default) | nessuna variabile d'ambiente | ASP: atomi nudi sul trail, `#sum{...}`, `#const n`, `=` |

Entrambi leggono lo stesso fatto `heuristic("...")`; cambia **come scrivi il corpo**. Gli
encoding BSP/PUP esistenti (`BSP_la.lp`, ...) sono scritti nello **stile SWI-Prolog** e si
eseguono con `LAZY_HEURISTIC_BACKEND=prolog`. Questa guida documenta a fondo quello stile e in
fondo (§8) riassume lo stile clingo-ausiliario.

---

## 1. Forma generale

```prolog
heuristic("heuristic(Target, Weight, Priority, Modifier) :- Body.").
```

Regole:

- Il fatto è `heuristic/1` (o `prolog_heuristic/1`) con **un unico argomento stringa**. Se
  l'argomento non è una stringa → errore `heuristic/1 expects a string rule`.
- La stringa, ripulita, **deve iniziare con `heuristic(`** → altrimenti `the rule string must
  start with heuristic(...)`. Il punto finale `.` viene aggiunto se manca.
- La **testa** è sempre `heuristic(Target, Weight, Priority, Modifier)` (arità 4).
- Puoi avere quanti `heuristic("...")` vuoi; ognuno è una regola indipendente.

> Non mischiare `__heuristic(...)` (approccio nativo) e `heuristic("...")` nello stesso run. In
> `clingo-prolog` gli atomi `__heuristic` vengono comunque **ignorati** (il parser nativo non
> è compilato in questo binario).

---

## 2. La testa: `heuristic(Target, Weight, Priority, Modifier)`

| Campo | Tipo | Significato |
|---|---|---|
| `Target` | atomo (con variabili legate nel corpo) | l'atomo su cui decidere, es. `b(X)` |
| `Weight` | **intero** | peso/bias della decisione (rank, vedi §6) |
| `Priority` | **intero** | priorità della decisione (rank, vedi §6) |
| `Modifier` | **`true` / `false`** | segno: `true` = assegna il target a *vero*, `false` = a *falso* |

Nel backend SWI, `Weight` e `Priority` **devono unificarsi a interi** e `Modifier` a `true`
oppure `false` (altrimenti: `weight and priority must be integers` / `modifier must be true or
false`). Tipicamente `Weight` è una variabile calcolata nel corpo con `is/2`, `Priority` è una
costante (`0`), `Modifier` è `true`/`false` costante.

---

## 3. Il corpo (stile SWI-Prolog): vocabolario disponibile

Il backend monta a runtime un piccolo programma Prolog che definisce questi predicati (li puoi
usare liberamente nel corpo della regola). Lo stato della ricerca è tenuto aggiornato in modo
incrementale tramite i fatti dinamici `true_atom/1` e `false_atom/1` (lo stato *Free* = atomo
assente da entrambi).

| Predicato | Definizione effettiva | Uso |
|---|---|---|
| `holds(A)` | `true_atom(A)` **oppure** `static_atom(A), \+ true_atom(A)` | A è **vero** sul trail (o è un fatto statico non contraddetto) |
| `holds_pos(A)` | `holds(A)` | alias di `holds/1` |
| `clingo_not(A)` | `false_atom(A)` | A è **falso** sul trail |
| `alpha_not(A)` | `\+ holds(A)` | A **non è (ancora) vero**: falso *o* indeciso |
| `target_available(A)` | `target_atom(A), \+ true_atom(A), \+ false_atom(A)` | A è un target **ancora libero** |
| `n(N)` | `n_value(N)` | la costante `n` inferita (vedi §5) |
| `aggregate_all/3` | `library(aggregate)` di SWI | aggregati Prolog (vedi §4) |
| `dyn_sum(Goal,T,S)` | `aggregate_all(sum(T),Goal,S)` | scorciatoia somma |
| `dyn_count(Goal,C)` | `aggregate_all(count,Goal,C)` | scorciatoia conteggio |
| `dyn_min(Goal,T,M)` | `aggregate_all(min(T),Goal,R)->M=R;M=0` | min con default 0 |
| `dyn_max(Goal,T,M)` | `aggregate_all(max(T),Goal,R)->M=R;M=0` | max con default 0 |

Oltre a questi: tutto il Prolog standard (`is/2`, confronti `>`, `=<`, `=:=`, ecc., taglio,
ecc.). La **semantica** della regola (vedi §7) si deduce dalla presenza di `clingo_not` nel
testo.

> **Importante sulla negazione.** `alpha_not(A)` è vero anche quando `A` è *indeciso* (semantica
> Alpha, ottimistica); `clingo_not(A)` è vero solo quando `A` è *già falso* (semantica Clingo,
> conservativa). Scegli in base a quando vuoi che l'euristica "scatti".

---

## 4. Aggregati (stile SWI-Prolog)

Usa `aggregate_all/3` di SWI con un goal che cammina sul trail tramite `holds/1`:

```prolog
aggregate_all(sum(Y), holds(c(Y)), S)      % S = somma delle Y tali che c(Y) è vero
aggregate_all(count, holds(c(_)), K)       % K = numero di c(_) veri
aggregate_all(max(Y), holds(c(Y)), M)      % M = massimo (fallisce se vuoto: usa dyn_max per default 0)
```

In alternativa le scorciatoie `dyn_sum/dyn_count/dyn_min/dyn_max` (queste ultime due
restituiscono `0` su insieme vuoto invece di fallire).

---

## 5. Predicati statici e la costante `n`

Alcuni predicati sono riconosciuti come **statici** (il loro contenuto è noto già a `init`):
**`x/1`, `item/1`, `dom/1`, `range/1`, `val/1`**. Vengono passati al backend come
`static_atom(...)`, quindi `holds(x(3))` funziona senza che `x(3)` sia "deciso" dal solver.

La costante **`n`** è **inferita automaticamente** come **massimo argomento di `x/1`**
(`x(1..n)` ⇒ `n` = quel massimo) ed è disponibile come `n(N)` nel corpo.

---

## 6. Rank delle decisioni (Priority, Weight, segno)

A ogni `decide()` il backend valuta le regole sullo stato corrente e raccoglie i candidati
`heuristic(Target, W, P, Mod)`; scarta quelli il cui target è già assegnato o non ha un
letterale noto al solver, e ordina i rimanenti per:

1. **Priority** decrescente;
2. a parità, **Weight** decrescente;
3. a parità, tie-break deterministico (stringa del target, poi letterale interno).

Vince il primo: il target viene deciso con segno `Mod` (`true` ⇒ letterale positivo, `false` ⇒
negativo). Non c'è soglia — anche `Priority` e `Weight` entrambi a `0` producono una decisione,
purché il target sia libero.

Varianti di ranking via ambiente (vedi §9): di default (`LAZY_PROLOG_RANKING` assente o ≠
`clingo-like`) si tengono tutti i candidati e si ordina globalmente; con
`LAZY_PROLOG_RANKING=clingo-like` si tiene prima il **migliore per ciascun target** (a parità di
`Priority`/`Weight` vince la regola dichiarata prima) e poi si ordina.

> **Differenza con l'approccio nativo.** Qui `Priority` pesa **sempre** nel confronto fra target
> diversi, con qualsiasi semantica. Nel propagatore `__heuristic` invece entra nel rank globale
> solo con `__semantics(alpha)`: con `clingo` risolve i conflitti fra regole dello stesso target
> e poi viene azzerata, e restano ordinati solo per peso (vedi
> [euristiche-native-sintassi.md](euristiche-native-sintassi.md), §8). Lì inoltre un target
> entra in coda solo se priorità o peso sono `> 0`.

---

## 7. Semantica Alpha vs Clingo

La semantica di **ogni regola** è dedotta dal testo:

- se la stringa contiene **`clingo_not(`** → semantica **Clingo**;
- altrimenti → semantica **Alpha**.

La differenza pratica è tutta in **quale negazione usi** nel corpo (`alpha_not` vs
`clingo_not`, §3) e in *quando* il candidato diventa applicabile (Clingo aspetta che gli atomi
siano decisi falsi; Alpha agisce anche su atomi liberi). Nel backend SWI i candidati prodotti
sono etichettati Alpha, ma è il corpo (`alpha_not`/`clingo_not`) a codificare il comportamento.

---

## 8. Stile **clingo ausiliario** (backend di default, senza `LAZY_HEURISTIC_BACKEND`)

Senza la variabile d'ambiente, le regole sono valutate costruendo al volo un **programma ASP
ausiliario**: gli atomi veri del trail diventano **fatti nudi** (`c(1).`), quelli falsi
`not_c(1).`, i predicati statici restano fatti (`x(1).`), `n` diventa `#const n=...`, e
`alpha_not(p(..))`/`clingo_not(p(..))` sono definiti automaticamente da `not_p(..)`. Quindi il
corpo si scrive in **ASP puro**, non in Prolog:

```prolog
% stile clingo-ausiliario (default)
heuristic("heuristic(a(X), 10, 0, true) :- item(X), alpha_not(c(X)).").
heuristic("heuristic(b(X), W, 0, true) :- x(X), alpha_not(c(X)), S = #sum { Y : c(Y) }, W = ((n+1)*S)+X.").
```

Note di stile rispetto al Prolog:

- gli atomi veri si citano **nudi** (`c(Y)`, `x(X)`), non con `holds(...)`;
- gli aggregati sono ASP (`S = #sum { Y : c(Y) }`), non `aggregate_all/3`;
- l'assegnazione del peso è ASP (`W = ((n+1)*S)+X`), non `W is ...`;
- `n` è il `#const` inferito; `alpha_not`/`clingo_not` restano disponibili.

La testa resta `heuristic(Target, Weight, Priority, Modifier)` con `Weight`/`Priority` numerici
e `Modifier` `true`/`false`.

---

## 9. Variabili d'ambiente

| Variabile | Effetto |
|---|---|
| `LAZY_HEURISTIC_BACKEND=prolog` | usa il backend **SWI-Prolog** (stile §3–4); altrimenti backend clingo-ausiliario (§8) |
| `LAZY_HEURISTIC_DEBUG=1` | log diagnostici (regole raccolte, programma ausiliario, decisioni) su stderr |
| `LAZY_PROLOG_STATS=1` | statistiche di timing del backend Prolog su stderr |
| `LAZY_PROLOG_RANKING=clingo-like` | variante di ranking: prima il migliore per target, poi ordine globale |

(valori veri accettati per i flag booleani: `1/true/TRUE/on/ON/yes/YES`.)

---

## 10. Regole, vincoli ed errori

- l'argomento di `heuristic/1` deve essere una **stringa**; la stringa deve **iniziare con
  `heuristic(`**; testa di arità 4.
- nel backend SWI: `Weight` e `Priority` devono unificarsi a **interi**, `Modifier` a
  **`true`/`false`**; un goal Prolog che fallisce nel parsing/esecuzione interrompe con errore.
- predicati `unknown` falliscono silenziosamente (`set_prolog_flag(unknown, fail)`): un typo in
  un predicato di corpo non solleva, semplicemente la regola non produce candidati — occhio.
- usa `holds/1` per leggere il trail: citare un atomo "nudo" nel backend SWI **non** funziona
  (gli atomi del trail sono `true_atom/false_atom`, non fatti diretti) — quello è lo stile
  clingo-ausiliario.

---

## 11. Esempi completi e funzionanti

**BSP, stile SWI-Prolog** (da `test_folder/encodings/BSP/BSP_la.lp`, eseguito con
`LAZY_HEURISTIC_BACKEND=prolog`):

```prolog
heuristic("heuristic(b(X), W, 0, true) :- aggregate_all(sum(Y), holds(c(Y)), S), holds(heuristic_base(Base)), holds(x(X)), target_available(b(X)), alpha_not(c(X)), W is Base*S+X.").
heuristic("heuristic(c(X), W, 0, true) :- aggregate_all(sum(Y), holds(b(Y)), S), holds(heuristic_base(Base)), holds(x(X)), target_available(c(X)), alpha_not(b(X)), W is Base*S+X.").
```

Lettura riga per riga della prima regola:

- testa `heuristic(b(X), W, 0, true)` — decidi `b(X)` a *vero* (`true`), priorità `0`, peso `W`;
- `aggregate_all(sum(Y), holds(c(Y)), S)` — `S` = somma delle `Y` con `c(Y)` vero sul trail;
- `holds(heuristic_base(Base))` — recupera `Base` (un fatto del programma);
- `holds(x(X))` — `X` spazia sul dominio statico `x/1`;
- `target_available(b(X))` — solo se `b(X)` è ancora libero;
- `alpha_not(c(X))` — e `c(X)` non è (ancora) vero (semantica Alpha);
- `W is Base*S+X` — calcola il peso.

**Stile clingo-ausiliario** (backend di default), equivalente concettuale:

```prolog
heuristic("heuristic(b(X), W, 0, true) :- x(X), alpha_not(c(X)), S = #sum { Y : c(Y) }, W = ((n+1)*S)+X.").
```

**Esempio minimo** (stile clingo-ausiliario, dai test): con `item(1..2)` e i guess `a/1,c/1`,

```prolog
heuristic("heuristic(a(X), 10, 0, true) :- item(X), alpha_not(c(X)).").
```

→ preferisci porre `a(X)` a vero (peso 10) finché `c(X)` non è vero.

---

## 12. Riferimento rapido (stile SWI-Prolog)

| Elemento | Sintassi |
|---|---|
| Fatto attivatore | `heuristic("...").` (o `prolog_heuristic("...").`) |
| Testa | `heuristic(Target, Weight, Priority, Modifier)` — `Modifier` ∈ `true`/`false` |
| Rank | `Priority` desc, poi `Weight` desc, poi tie-break deterministico |
| Atomo vero sul trail | `holds(A)` (o `holds_pos(A)`) |
| Atomo falso | `clingo_not(A)` |
| Atomo non vero (free/false) | `alpha_not(A)` |
| Target ancora libero | `target_available(A)` |
| Costante n | `n(N)` (inferita da `x/1`) |
| Aggregati | `aggregate_all(sum(T)/count/min(T)/max(T), Goal, V)`, `dyn_sum/dyn_count/dyn_min/dyn_max` |
| Aritmetica | `V is Expr` |
| Predicati statici | `x/1, item/1, dom/1, range/1, val/1` |
| Backend SWI | `LAZY_HEURISTIC_BACKEND=prolog` |
| Guidare le decisioni | flag clingo `--heuristic=Domain` |
