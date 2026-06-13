# Analisi: True / Must-be-True nel propagatore, e fattibilità di HRP e A\*

Documento di analisi (non di implementazione) richiesto durante il refactoring.
Riferimento principale: *Romero et al., «Domain-Specific Heuristics in Answer Set
Programming: A Declarative Non-Monotonic Approach»* (la base del solver **Alpha**),
in `paper/Romero 1 - ...pdf`.

---

## 1. «True» e «Must-be-True» dentro alpha: si può replicare nel nostro propagatore?

### 1.1 Cosa dice il paper (semantica esatta)

Alpha lavora su **assegnamenti parziali a 4 valori** per atomo:

- **F** (false),
- **U** (unassigned),
- **M** (*must-be-true*): «l'atomo *dovrà* diventare vero per derivazione in una
  soluzione corretta che estende l'assegnamento corrente, ma *nessuna derivazione è
  ancora stata trovata*» (paper, righe 198–199);
- **T** (true): vero **e già giustificato** da una regola che lo deriva (riga 207).

Vincolo strutturale: ogni atomo vero è anche must-be-true, cioè `A_T ⊆ A_M` (riga 205).
Quando un atomo M trova un supporto fondante, *promuove* da M a T (riga 207).

Il punto cruciale per noi è la riga **231–240**:

> «Storicamente il valore must-be-true fu introdotto [in smodels]; la stessa efficienza
> fu poi ottenuta senza must-be-true usando i *source-pointers*. […] I solver in stile
> **clasp rappresentano must-be-true *implicitamente*, tramite lo stato interno dei
> source-pointer e il risultato della unfounded-set propagation**, mentre noi [Alpha]
> abbiamo scelto di rappresentare must-be-true *esplicitamente* come valore di verità.»

E (riga 241): rappresentarlo esplicitamente «permette euristiche domain-specific più
fini».

### 1.2 Conseguenza diretta per il NOSTRO caso

Entrambi i nostri backend (native C++ e Prolog/SWI) sono propagatori **sopra
clingo/clasp**, non sopra Alpha. L'interfaccia che il propagatore vede
(`Clingo::Assignment`) espone per ogni letterale **solo tre stati**: `True`, `False`,
`Free` (`is_true / is_false / truth_value`). **Non esiste un quarto valore M.**

In altre parole: il must-be-true nel nostro stack **c'è già**, ma è *sepolto* dentro la
unfounded-set propagation di clasp e **non è esposto** all'API del propagatore. Questo è
esattamente lo scenario «clasp implicito» descritto dal paper. Alpha può distinguere
T da M perché il valore M è di prima classe nel suo core; noi no.

Quindi la risposta onesta alla domanda «si può implementare la stessa logica?» è:

- **Replica *fedele* (T vs M come in Alpha): no**, non attraverso l'API pubblica di
  clingo. Richiederebbe di *patchare libclasp* per esporre la weak-truth /
  lo stato dei source-pointer al propagatore. È invasivo, fragile tra le versioni di
  clingo, e contraddice l'obiettivo «usare il backend clasp standard». Di fatto si
  rifarebbe il lavoro che Alpha fa già: se serve il T/M fedele, **la strada giusta è
  usare Alpha**, non clingo.

- **Approssimazione *utile* nello spirito di T/M: sì, fattibile**, con sforzo contenuto.
  Vedi sotto.

### 1.3 Cosa abbiamo già che assomiglia a T/M

La nostra **semantica `alpha`** è già un primo pezzo del puzzle, ma sull'asse della
*negazione*, non su quello T/M:

- `alpha_not(p)` (Prolog) / `__n_p` con `__semantics(alpha)` (native) = «p **non è
  vero**» → soddisfatta se p è **F oppure U**.
- `clingo_not(p)` / `__semantics(clingo)` = «p è **F**» (deve essere proprio falso).

Inoltre, in semantica `alpha` gli aggregati usano il **valore parziale corrente**
(chiave runtime mancante = 0), mentre in `clingo` si attivano solo a **sorgenti
completamente determinate**. Questo è coerente col «ragionare su assegnamenti parziali»
del paper (righe 96–97), ma **non** introduce ancora il valore M.

### 1.4 Approssimazione di M proponibile (e quanto costa)

L'idea: introdurre uno stato per-target **`forced` ("M-approx")** = «il target è ancora
`Free`, ma è di fatto *costretto* a diventare vero perché tutte le alternative negative
sono già `False`». È un'approssimazione *sintattica/strutturale* di M calcolabile dal
solo assegnamento visibile, senza unfounded-set.

Nel **propagatore native** l'infrastruttura c'è già quasi tutta:
- `target_states_` mantiene già lo stato per atomo target;
- il propagatore già *watcha* letterali di corpo e mantiene aggregati incrementali in
  `propagate()`/`undo()`.

Servirebbe:
1. per ogni target `p(t)`, watchare anche il/i letterale/i del suo «complemento»
   (es. `not_assigned_*` nelle nostre codifiche PUP, o il `c(X)` rispetto a `b(X)` in
   BSP): quando il complemento diventa `False` e `p(t)` è ancora `Free`, marcare `p(t)`
   come `forced` (M-approx);
2. un nuovo ramo in `decide()` / `refresh_target` (vicino a `update_best_by_local_priority`)
   che dia priorità ai target `forced` — cioè «chiudi prima gli M», che è proprio l'uso
   euristico che il paper attribuisce a M;
3. opzionale: un nuovo **modificatore** o **flag di semantica** (es.
   `__semantics(alpha_mbt)`) per attivarlo senza rompere gli encoding esistenti.

Stima: **moderata** — un flag in `target_states_`, qualche watch in più, un branch
nell'ordinamento. Giorni, non settimane; tutto dentro `heuristic_propagator.{hh,cc}` e
`heuristic_types.hh`, nessun tocco a clasp.

Nel **backend Prolog** il costo è anche minore *una volta* che il C++ calcola l'M-approx:
basta esporre un nuovo predicato foreign `must_be_true(p(X))` (accanto agli esistenti
`holds/1`, `alpha_not/1`, `target_available/1`) che interroga lo stesso `target_states_`.
Le regole `heuristic("...")` potrebbero allora scrivere `must_be_true(assigned_...(X,U))`
nel corpo. Glue minima; la difficoltà resta tutta nel punto (1) lato C++.

### 1.5 Sintesi punto 1

| | Fedele (T/M come Alpha) | Approssimato (M-approx «forced») |
|---|---|---|
| Native | Richiede patch a libclasp → **alto/sconsigliato** | **Moderato**, contenuto nel propagatore |
| Prolog | Idem (stesso segnale mancante) | **Basso** sopra l'M-approx native (solo foreign pred) |
| Resa | Massima | Cattura «chiudi prima gli atomi forzati» |

Raccomandazione: **non** inseguire il T/M fedele su clingo (lì è giustamente *implicito*);
se serve davvero quella semantica, è il caso d'uso di Alpha. Per i nostri esperimenti,
l'**M-approx «forced»** è il rapporto valore/sforzo migliore e si aggancia all'asse
`alpha` che già abbiamo.

---

## 2. HRP e A\*: almeno uno è facilmente aggiungibile a ga/gc/la/lc?

### 2.1 Cosa sono (dal paper Romero)

- **HRP = House Reconfiguration Problem** (riga 1291: «due problemi di configurazione,
  varianti astratte di problemi tipici di configurazione»). È un problema di
  **assegnamento/riconfigurazione** con vincoli di capacità e relazionali — la stessa
  *famiglia* del PUP che già supportiamo.
- **A\*** (Sez. 6.4, righe 2084–2090): **non è un dominio**, è una *strategia di ricerca
  best-first* (f(n) = g(n) + h(n)) implementata **dichiarativamente come euristica** in
  ASP «per la prima volta», e poi applicata a due problemi di ricerca su spazio di stati.

### 2.2 HRP nelle nostre 4 casistiche → **facile**

HRP è strutturalmente isomorfo al PUP: si *guessa* un assegnamento (oggetto → entità) con
le solite regole a doppia negazione (`assigned/not_assigned`), e l'euristica di dominio è
del tipo «assegna ogni oggetto alla prima locazione fattibile», pesata da aggregati su
ciò che è correntemente assegnato. Questo entra **direttamente** nel nostro template:

- **gc** (ground, clingo): `#heuristic assigned(O,L) : assignable(O,L), not not_assigned(O,L), W=#agg{...}. [W, true]`
- **ga** (ground, alpha): stessa cosa con la variante alpha del corpo/aggregato;
- **lc / la** (lazy): traduzione meccanica come per PUP →
  - Prolog: `heuristic("heuristic(assigned(O,L), W, Pr, true) :- holds(assignable(O,L)), target_available(assigned(O,L)), clingo_not|alpha_not(not_assigned(O,L)), aggregate_all(...), W is ...").`
  - native: `__heuristic(__target(assigned), assignable, __n_not_assigned, __bind(...), __weight(...), __priority(...), __semantics(clingo|alpha), __modifier(true)).`

L'unica accortezza è la stessa già incontrata nel PUP: gli aggregati con **join** fra due
predicati vanno precompilati in un predicato ausiliario derivato e poi contati con
`__count`/`__sum` filtrati sul target (vedi `encodings-native/2_PUP/PUP_la.lp`). L'euristica
tipica dell'HRP è in genere *più semplice* di quella del PUP (meno termini d'aggregato).

**Verdetto HRP: facilmente aggiungibile a tutte e 4 le casistiche.** Si aggancia come
terzo dominio `3_HRP` accanto a `1_BSP`/`2_PUP`, sia in `encodings-prolog` sia in
`encodings-native`, e ai 4 script di benchmark (basta il pattern già scritto in
`_bench_lib.sh`, con `run_hrp` modellato su `run_pup`). È la scelta consigliata.

### 2.3 A\* nelle nostre 4 casistiche → **non facile**

A\* richiede tre cose che il nostro template *non* offre:

1. **Frontiera best-first**: ordinare l'espansione dei nodi per `f = g + h`. Le nostre
   euristiche producono un *peso statico-per-decisione* su atomi di assegnamento; non
   gestiscono una frontiera che si ri-ordina dinamicamente a ogni passo.
2. **g(n) dipendente dal cammino**: g è il costo del percorso fin qui, funzione
   dell'*intero assegnamento parziale*; i nostri pesi sono aggregati locali su atomi
   correntemente veri — si può *approssimare* g, ma non è il costrutto naturale.
3. **Priorità/livelli dinamici e ragionamento non-monotono** sull'assegnamento parziale,
   che nel paper si appoggiano proprio alla distinzione **T vs M** (punto 1) per
   correttezza/efficienza. Quel segnale, sul nostro clasp, **non c'è** (vedi §1.2).

Quindi A\* è bloccato in parte dalla *stessa* limitazione del punto 1 (M non esposto) e in
parte dal fatto che è una *strategia di ricerca*, non un encoding di dominio: servirebbe un
motore euristico con priorità dinamiche e gestione di frontiera, ben oltre l'attuale
`__heuristic`/`heuristic(...)`.

**Verdetto A\*: non facilmente aggiungibile.** Alto sforzo, dipendenza dal T/M fedele.

### 2.4 Raccomandazione punto 2

Aggiungere **HRP** ai test (le 4 casistiche `ga/gc/la/lc`, entrambi i backend): è
PUP-simile, già coperto dal nostro template e dalla pipeline di benchmark. **Rinviare
A\***: ha senso solo dopo (ed è in parte subordinato a) l'M-approx del punto 1, e comunque
richiede un'estensione del motore euristico, non un nuovo encoding.

---

## Appendice — stato del refactoring (contesto)

- `clingo-native` = propagatore **C++ puro** (`heuristic_parser/propagator/aggregate`,
  fatti `__heuristic`). `clingo-prolog` = propagatore con **backend SWI-Prolog**
  (`swi_prolog_heuristic_backend`, stringhe `heuristic("...")`). `clingo-modified` (legacy
  misto) **eliminato**.
- Encoding riordinati in `test_folder/encodings-prolog` e `test_folder/encodings-native`,
  con sottocartelle `1_BSP` / `2_PUP`. I file lazy `la/lc` (e `la_aux/la_co` per BSP) sono
  stati **tradotti nel DSL nativo** e **verificati** col binario `clingo-native`
  (es. PUP `la` alpha: 26 choices vs 266 del baseline su `double-20`).
- Script di benchmark per-backend: `1_native_bsp`, `1_prolog_bsp`, `2_native_pup`,
  `2_prolog_pup` (+ `_bench_lib.sh`).
