# Riepilogo operativo per la tesi

Data: 2026-05-21

## Tesi centrale

La conclusione forte non deve essere "lazy e' piu' veloce". La formulazione piu' corretta e difendibile e':

> Le euristiche lazy scambiano la piena materializzazione a grounding time con una valutazione incrementale a solving time, rendendo praticabili euristiche aggregate che sotto la semantica nativa di `#heuristic` possono generare una componente ground enorme.

Il contributo scientifico e' quindi triplo:

1. una rappresentazione lazy dichiarativa per euristiche aggregate;
2. una semantica operativa distinta tra stile Alpha e stile clingo-like;
3. una valutazione sperimentale che separa grounding, solving, semantica e forma dell'encoding.

## Stato attuale del progetto

Punti gia' forti:

- esiste una modifica reale di `clingo` in `clingo-modified/libclingo`;
- il propagatore e' registrato automaticamente in `clingo_app.cc`;
- la pipeline `#heuristic -> converter AST -> __heuristic facts -> propagator` e' implementata;
- il converter `test_folder/tools/asp_heuristic_converter.py` usa `clingo.ast`;
- il benchmark BSP raccoglie metriche separate di grounding/solving;
- i grafici BSP sono gia' generati sotto `thesis/Tesi_Lazy_Heuristics/figures/bsp`;
- i capitoli `1 - Introduzione.tex`, `2 - Metodologia.tex`, `3 - Risultati.tex` e `4 - Discussione-e-Conclusione.tex` contengono gia' una prima struttura solida.

Punti ancora deboli:

- la definizione scientifica del problema va resa piu' esplicita;
- la semantica lazy va presentata come oggetto formale, non solo come implementazione;
- i risultati vanno sincronizzati con l'ultimo CSV, perche' alcuni valori nel capitolo risultati sembrano riferirsi a run precedenti;
- manca una misura diretta dell'overhead del propagatore;
- PUP e' ancora un placeholder: `benchmark_pup.sh` e' disabilitato e le cartelle PUP risultano vuote;
- mancano figure architetturali non sperimentali: pipeline, lifecycle di un candidato, refresh/watches.

## Definizione scientifica da scrivere meglio

### Problema

Una direttiva nativa:

```prolog
#heuristic A : Body. [W@P, M]
```

viene groundata prima della ricerca. Se `W` o `P` dipendono da un aggregato, per esempio:

```prolog
S = #sum { Y : c(Y) }
```

il grounder deve materializzare combinazioni sufficienti a rappresentare i possibili valori ground del corpo e del peso. Nel caso BSP questo porta a una crescita rapida degli oggetti `#heuristic` ground.

La tesi deve chiarire bene perche' il problema e' specifico delle heuristic directives:

- un aggregate constraint ordinario puo' essere compilato in strutture proposizionali/weight constraints che partecipano alla propagazione del programma;
- una direttiva `#heuristic`, invece, non definisce vincoli semantici del programma, ma dati di guida per il solver;
- il grounder materializza comunque tali dati prima del solving;
- il costo puo' quindi crescere molto anche se l'euristica non cambia gli answer set.

### Contributo

La formulazione consigliata:

> Introduciamo una rappresentazione lazy per euristiche aggregate che mantiene compatta la descrizione ground della direttiva e ritarda la valutazione di attivazione, peso e priorita' al solving time.

Cosa viene spostato dal grounding al solving:

- valutazione dei body literals rispetto all'assegnamento corrente;
- valutazione degli aggregati dinamici;
- computazione di peso e priorita';
- aggiornamento dell'effetto euristico attivo.

Cosa rimane statico:

- target predicate;
- struttura sintattica della regola lazy;
- espressioni aritmetiche parse in AST;
- set dei predicati osservati;
- mapping tra tuple ground, literal e candidate.

Assunzioni correnti:

- target e body indicizzabili tramite tuple numeriche;
- aggregati supportati: `sum`, `count`, `min`, `max`;
- espressioni aritmetiche limitate a costanti, `self`, variabili bound, `__add`, `__sub`, `__mul`;
- registrazione sequenziale del propagatore.

Cosa non e' supportato o non va rivendicato:

- non e' un lazy grounder generale;
- non elimina il grounding del programma base;
- non implementa fedelmente `init` e `factor`;
- non riproduce il tie-break interno completo di clingo;
- non dimostra equivalenza prestazionale universale tra lazy e native.

## Semantica lazy da formalizzare

Questa sezione dovrebbe diventare una sottosezione autonoma, per esempio "Semantics of Lazy Heuristics".

Definizioni minime:

- **Target atom**: atomo ground su cui una regola lazy puo' produrre un effetto euristico.
- **Candidate**: istanza runtime di un template lazy per uno specifico target ground.
- **Activation condition**: un candidato e' attivo se il target e' non assegnato, i body positivi sono soddisfatti, i body negativi sono soddisfatti secondo la semantica scelta e gli aggregati necessari sono valutabili.
- **Body matching**: associazione tra argomenti del target, argomenti dei body predicates e variabili interne.
- **Aggregate evaluation**: lettura incrementale di uno stato aggregato associato a una sorgente e a eventuali filtri target-specific.
- **Refresh behavior**: quando un literal osservato cambia, il propagatore aggiorna aggregati e candidati dipendenti.
- **Priority computation**: `@P` risolve conflitti tra effetti applicabili allo stesso target/modifier; non e' una chiave globale tra target.
- **Global ranking**: dopo la risoluzione locale, i target attivi vengono ordinati per livello risolto e literal tie-break.

Distinzione semantica da enfatizzare:

- **Alpha-style**: `not a` e' soddisfatto quando `a` non e' vero; gli aggregati possono essere letti sullo stato parziale.
- **Clingo-like**: `not a` e' soddisfatto quando `a` e' falso/determinato secondo il criterio implementato; gli aggregati possono richiedere sorgenti determinate.

Questa distinzione e' cruciale: `la` non e' semplicemente una versione piu' efficiente di `gc`, perche' cambia il momento di applicazione della guida euristica.

## Architettura da raccontare

Pipeline consigliata:

```text
#heuristic native
    |
    v
converter AST-based
    |
    v
__heuristic(...) facts
    |
    v
normal clingo grounding
    |
    v
scan symbolic atoms
    |
    v
parse HeuristicRuleTemplate
    |
    v
build GroundLiteralIndex
    |
    v
materialize RuntimeHeuristicCandidate
    |
    v
register watches
    |
    v
incremental aggregate refresh
    |
    v
local target resolution
    |
    v
decision ranking / decide()
```

Componenti da descrivere nel capitolo metodologia:

- `GroundLiteralIndex`: mappa predicato/tupla numerica -> literal ground;
- `RuntimeHeuristicCandidate`: istanza runtime collegata a target, body, bindings e aggregati;
- `candidate_ids_by_aggregate_`: collega ogni aggregato runtime ai candidati da aggiornare;
- `candidate_ids_to_refresh_by_lit_`: collega literal osservati ai candidati da rinfrescare;
- `aggregate_keys_to_refresh_by_lit_`: collega literal osservati agli aggregati da aggiornare;
- `TargetHeuristicState`: risoluzione locale degli effetti su uno stesso target;
- `active_decision_ranks_`: ranking globale consultato da `decide()`.

Figure minime da aggiungere:

- architettura completa del sistema;
- pipeline converter -> facts -> propagator;
- lifecycle di un candidate;
- schema watches/refresh;
- confronto visuale tra esplosione native e rappresentazione lazy.

## Esperimenti

### BSP

BSP e' gia' la base sperimentale principale. L'ultimo CSV disponibile e':

```text
test_folder/results/bsp_results.csv
```

Metadata principali:

- data run: 2026-05-21 00:29:42 +02:00;
- build: Release;
- timeout: 180s;
- limite memoria: 10 GiB;
- seed: 1 e 2;
- `n`: 10..200 step 10;
- varianti attive: `ga_dyn`, `ga`, `gc_noheur`, `gc`, `la_aux`, `la_co`, `la`, `lc`.

Valori medi a `n=100` nell'ultimo CSV:

| Variant | Ground heuristics | Lazy facts | Variables | Total s | Solving s | Choices | Conflicts | Memory MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `gc_noheur` | 0 | 0 | 20,300 | 69.32 | 14.90 | 63,255 | 42,903 | 3,274.8 |
| `gc` | 1,010,200 | 0 | 1,030,606 | 79.47 | 22.22 | 32,514 | 20,888 | 3,755.1 |
| `ga` | 1,010,200 | 0 | 20,406 | 68.47 | 12.79 | 54,147 | 36,573 | 3,315.6 |
| `la` | 0 | 2 | 20,300 | 54.41 | 0.02 | 100 | 0 | 3,275.0 |
| `lc` | 0 | 2 | 20,300 | 72.19 | 17.42 | 63,255 | 42,903 | 3,273.8 |

Punti di rottura registrati:

| n | Variant | Failure |
| ---: | --- | --- |
| 60 | `la_aux` | timeout |
| 70 | `ga_dyn` | timeout |
| 110 | `gc` | timeout |
| 120 | `ga` | timeout |
| 130 | `gc_noheur` | timeout |
| 130 | `lc` | timeout |
| 140 | `la` | memory limit |

Massimo `n` con status `ok` nell'ultimo CSV:

| Variant | Max n ok |
| --- | ---: |
| `ga_dyn` | 60 |
| `ga` | 110 |
| `gc_noheur` | 120 |
| `gc` | 100 |
| `la_aux` | 50 |
| `la_co` | 200 |
| `la` | 130 |
| `lc` | 120 |

Nota importante: il capitolo `3 - Risultati.tex` contiene alcuni valori che sembrano precedenti rispetto al CSV corrente. Prima della consegna va sincronizzato con `bsp_results.csv` e `bsp_failures.txt`.

### Lettura scientifica di BSP

Risultato A: riduzione grounding euristico.

- `gc` e `ga` materializzano oltre un milione di oggetti heuristic a `n=100`;
- `la` e `lc` mantengono due fact lazy;
- questa e' la prova piu' forte del contributo rappresentazionale.

Risultato B: tradeoff grounding/solving.

- `la` ha solving quasi nullo a `n=100`, ma va interpretata come semantica Alpha-style;
- `lc` mantiene la rappresentazione lazy ma mostra un profilo search simile a `gc_noheur`;
- quindi la tesi deve separare "compressione della rappresentazione" da "qualita' della guida euristica".

Risultato C: scalabilita' e fallimenti.

- `gc` fallisce prima per timeout a `n=110`;
- `la` arriva piu' avanti ma poi incontra limite memoria a `n=140`;
- `la_aux` conferma che materializzare il body in ausiliari puo' reintrodurre costo di grounding.

### PUP

Stato attuale:

- `test_folder/benchmarks/benchmark_pup.sh` e' disabilitato;
- `test_folder/encodings/PUP` non contiene encoding;
- `test_folder/instances/PUP_instances` non contiene istanze;
- `gen_graphs.py` ha gia' supporto storico/previsto per PUP, ma mancano dati reali.

Prossime azioni:

1. decidere quali famiglie PUP usare (`double`, `doublev`, ausiliaria, lazy);
2. inserire encoding e istanze;
3. riattivare `benchmark_pup.sh`;
4. generare CSV separati, per esempio `pup_double_results.csv` e `pup_doublev_results.csv`;
5. aggiungere una sezione risultati PUP solo dopo avere dati riproducibili.

## Overhead del propagatore

Questa e' la parte sperimentale piu' mancante. Anche senza profiling sofisticato, conviene aggiungere contatori interni e stamparli nelle statistiche o in debug.

Metriche consigliate:

- numero di template letti;
- numero di candidate materializzati;
- numero di watches registrate;
- numero di aggregate runtime key;
- numero di refresh per literal;
- numero di refresh per aggregato;
- numero di candidate evaluation;
- numero di target resolution;
- numero di chiamate a `decide`;
- numero di decisioni effettivamente fornite dal propagatore;
- tempo totale speso in `propagate`;
- tempo totale speso in `undo`;
- tempo totale speso in `decide`;
- picco di target attivi.

Confronti utili:

- lazy con refresh incrementale vs refresh globale, anche solo su una build sperimentale;
- `la` vs `lc`, per isolare il costo della semantica;
- direct lazy vs aux lazy, per misurare quanto grounding viene reintrodotto dagli ausiliari;
- `gc_noheur` vs `lc`, per stimare overhead lazy quando la ricerca resta simile.

## Roadmap prioritaria

1. Sincronizzare `3 - Risultati.tex` con l'ultimo CSV BSP.
2. Completare la formalizzazione di problema/contributo in introduzione.
3. Aggiungere una sottosezione esplicita sulla semantica lazy.
4. Aggiungere figure architetturali non sperimentali.
5. Aggiungere contatori minimi per l'overhead del propagatore.
6. Decidere se PUP entra davvero nella tesi; se entra, popolare encoding/istanze e riattivare il benchmark.
7. Scrivere meglio limitations/correctness: cosa e' equivalente, cosa e' solo ispirato a clingo, cosa e' Alpha-style.
8. Rifinire la sezione converter: trasformazioni supportate, casi rifiutati, garanzie.
9. Rafforzare threats to validity: singolo dominio, due seed, hardware, timeout, stima grounding derivata.
10. Chiudere con una conclusione prudente ma forte: scalabilita' del componente euristico, non superiorita' assoluta.

## Mapping sui file della tesi

`1 - Introduzione.tex`:

- aggiungere spiegazione rigorosa dell'esplosione di grounding;
- esplicitare meglio problema, obiettivo, contributo e non-obiettivi;
- anticipare la distinzione Alpha vs clingo-like.

`2 - Metodologia.tex`:

- aggiungere figura pipeline;
- aggiungere lifecycle del candidate;
- espandere la sezione semantica;
- distinguere rappresentazione, materializzazione, refresh, ranking.

`3 - Risultati.tex`:

- sincronizzare tabelle con `bsp_results.csv`;
- aggiungere punti di rottura da `bsp_failures.txt`;
- separare chiaramente claim rappresentazionale e claim search;
- aggiungere eventuali metriche overhead se implementate.

`4 - Discussione-e-Conclusione.tex`:

- rafforzare threats/limitations;
- dichiarare esplicitamente che non e' lazy grounding generale;
- concludere sul tradeoff grounding/solving.

## Definition of done

La tesi e' scientificamente solida quando:

- il lettore capisce perche' `#heuristic` con aggregati esplode in grounding;
- la rappresentazione lazy e' definita indipendentemente dal codice;
- Alpha-style e clingo-like non sono confuse;
- i grafici dimostrano riduzione grounding, tradeoff solving e scalabilita';
- i fallimenti sono discussi e non nascosti;
- l'architettura del propagatore e' leggibile come contributo tecnico;
- le limitazioni sono dichiarate senza indebolire il contributo;
- la conclusione non promette velocita' universale, ma praticabilita' di euristiche altrimenti troppo costose da materializzare.
