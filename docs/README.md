# Build di `clingo-modified`

Questi appunti servono per ricompilare la versione modificata di clingo che sta nella cartella `clingo-modified`.

## Idea generale

La build usa due strumenti:

- `cmake`: prepara la cartella di build. Legge i file `CMakeLists.txt`, controlla il compilatore, le opzioni e genera i file necessari per compilare.
- `ninja`: compila davvero i file C/C++ usando le istruzioni generate da CMake.

Quindi di solito ci sono due fasi diverse:

1. configurazione con `cmake`;
2. compilazione con `ninja`, oppure con lo script `recompile.sh`.

La configurazione si fa raramente: la prima volta, oppure quando vuoi cambiare opzioni importanti come `Debug`/`Release`.
La compilazione si fa ogni volta che modifichi il codice C++.

## Prima configurazione con CMake

Dalla root del repository, cioe' dalla cartella che contiene `clingo-modified`, esegui:

```bash
cmake -S clingo-modified -B clingo-modified/build -G Ninja -DCMAKE_BUILD_TYPE=Release
```

Significato delle opzioni:

- `-S clingo-modified`: indica a CMake dove sono i sorgenti, cioe' dove si trova il `CMakeLists.txt` principale.
- `-B clingo-modified/build`: indica dove creare la cartella di build. I file compilati finiscono qui, separati dai sorgenti.
- `-G Ninja`: dice a CMake di generare una build per Ninja.
- `-DCMAKE_BUILD_TYPE=Release`: compila in modalita' ottimizzata. E' quella da usare per benchmark e test di performance.

Se invece vuoi una build piu' comoda da debuggare, puoi usare:

```bash
cmake -S clingo-modified -B clingo-modified/build -G Ninja -DCMAKE_BUILD_TYPE=Debug
```

Pero' `Debug` e' piu' lenta e non usa le ottimizzazioni di `Release`.

## Ricompilare dopo una modifica

Dopo aver modificato un file `.cc` o `.hh`, normalmente non serve rilanciare tutto il comando CMake.
Usa lo script:

```bash
./test_folder/tools/recompile.sh
```

Lo script fa queste cose:

- trova automaticamente la root del repository;
- entra in `clingo-modified/build`;
- controlla se la build e' configurata in `Debug` e avvisa;
- esegue `ninja`.

In pratica e' una scorciatoia per:

```bash
cd clingo-modified/build
ninja
```

Il vantaggio di Ninja e' che ricompila solo quello che e' cambiato. Se modifichi un file, non ricompila tutto il progetto da zero: ricostruisce solo i pezzi necessari e poi rilinka gli eseguibili/librerie che dipendono da quel file.

## Comando alternativo senza entrare nella build directory

Se non vuoi usare direttamente `ninja`, puoi chiedere a CMake di chiamare lui il sistema di build configurato:

```bash
cmake --build clingo-modified/build -j2
```

Questo comando usa il generator scelto durante la configurazione. Nel nostro caso, siccome abbiamo configurato con `-G Ninja`, CMake chiamera' Ninja sotto il cofano.

`-j2` significa "usa 2 job in parallelo". Puoi aumentarlo se vuoi compilare piu' velocemente, ad esempio:

```bash
cmake --build clingo-modified/build -j8
```

## Dove finisce l'eseguibile

Dopo la compilazione, l'eseguibile modificato di clingo si trova qui:

```bash
clingo-modified/build/bin/clingo
```

Puoi controllare che esista con:

```bash
ls -l clingo-modified/build/bin/clingo
```

E puoi eseguirlo direttamente, ad esempio:

```bash
./clingo-modified/build/bin/clingo --version
```

## Quando rilanciare CMake

Usa solo `./test_folder/tools/recompile.sh` quando hai modificato codice normale, per esempio:

- file `.cc`;
- file `.hh`;
- piccoli cambi interni alla logica del propagatore.

Rilancia invece il comando `cmake -S ... -B ...` quando:

- la cartella `clingo-modified/build` non esiste;
- hai cambiato opzioni di build, per esempio da `Debug` a `Release`;
- hai modificato file `CMakeLists.txt`;
- CMake o Ninja si lamentano di una configurazione incoerente.

Per riconfigurare in `Release` una build gia' esistente:

```bash
cmake -S clingo-modified -B clingo-modified/build -G Ninja -DCMAKE_BUILD_TYPE=Release
```

Poi ricompila:

```bash
./test_folder/tools/recompile.sh
```





## Benchmark BSP

Questa sezione documenta la suite sperimentale BSP usata per confrontare:

```text
1. semantica: Clingo vs Alpha
2. strategia: ground-and-solve vs lazy
3. forma dell'encoding: diretto vs ausiliario
```

Gli script principali sono:

```bash
test_folder/benchmarks/benchmark_bsp.sh
test_folder/benchmarks/benchmark_runner.py
test_folder/tools/gen_graphs.py
test_folder/generate_graphs.sh
```

`benchmark_bsp.sh` itera su varianti, valori di `n` e seed. `benchmark_runner.py` esegue una singola run, estrae le statistiche da Clingo e aggiunge una riga al CSV. `gen_graphs.py` legge il CSV e genera i grafici.

I risultati BSP vengono salvati in:

```bash
test_folder/results/bsp_results.csv
```

I grafici BSP vengono salvati in:

```bash
test_folder/results/graphs/bsp/standard/
test_folder/results/graphs/bsp/no_ga/
```

## Prima Suite Da Eseguire

Per ora la suite di default e' quella esplorativa da 60 secondi con una sola ripetizione:

```bash
TIMEOUT_SECONDS=60 REPEATS=1 N_START=10 N_END=50 N_STEP=10 \
BSP_VARIANTS="gc gc_aux ga la lc la_aux" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Quindi dalla root del repository basta eseguire:

```bash
bash test_folder/benchmarks/benchmark_bsp.sh
```

Questo testa:

```text
n:        10, 20, 30, 40, 50
varianti: gc, gc_aux, ga, la, lc, la_aux
repeat:   1
timeout:  60 secondi per singola run
```

`STOP_VARIANT_ON_MEMORY=1` e' attivo di default. Se una variante raggiunge il
limite di memoria a un certo valore di `n`, lo script la ferma per i valori
successivi e continua invece con le altre varianti. I timeout non fermano la
variante: vengono registrati come `status=timeout` e il benchmark passa al
valore di `n` successivo. Per disattivare lo stop su memoria:

```bash
STOP_VARIANT_ON_MEMORY=0 \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Il limite superiore dello sweep resta `N_END`: per continuare a valori di `n` piu' grandi, aumenta `N_END`.

## Varianti BSP

Set principale consigliato:

```text
gc      = ground-and-solve, semantica Clingo, #heuristic nativa
gc_aux  = ground-and-solve, semantica Clingo, aggregato spostato in ausiliario
ga      = ground-and-solve, semantica Alpha
la      = lazy, semantica Alpha
lc      = lazy, semantica Clingo
la_aux  = lazy, semantica Alpha, aggregato materializzato in ausiliario
```

Variante disponibile ma non inclusa nel default:

```text
la_co   = lazy Alpha con vincolo BSP ottimizzato/lineare
```

Per cambiare il set:

```bash
BSP_VARIANTS="gc lc" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

## Parametri Utili

Cambiare intervallo di `n`:

```bash
N_START=10 \
N_END=100 \
N_STEP=10 \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Cambiare ripetizioni e timeout:

```bash
REPEATS=3 \
TIMEOUT_SECONDS=300 \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Cambiare limite memoria:

```bash
MEM_LIMIT_BYTES=$((16 * 1024 * 1024 * 1024)) \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Forzare un binario Clingo specifico:

```bash
CLINGO_MOD=./clingo-modified/build/bin/clingo \
bash test_folder/benchmarks/benchmark_bsp.sh
```

## Singola Run Manuale

Esempio con `lc` e `n=50`:

```bash
python3 test_folder/benchmarks/benchmark_runner.py \
  --clingo ./clingo-modified/build/bin/clingo \
  --encoding test_folder/encodings/BSP/BSP_lc.lp \
  --instance test_folder/instances/BSP_instances/BSP_range.lp \
  --variant lc \
  --semantics clingo \
  --size 50 \
  --seed 1 \
  --csv test_folder/results/manual_bsp.csv \
  --constant n=50 \
  --models 1 \
  --timeout 60 \
  --memory-bytes $((32 * 1024 * 1024 * 1024)) \
  --domain-heuristic
```

## Origine Dei Dati

Il CSV contiene sia metriche numeriche per i grafici sia colonne diagnostiche:

```text
n, variant, seed
status, failure_reason, exit_code, memory_limit_hit
solving_s, total_s, grounding_s
choices, conflicts, restarts
rules, variables, memory_mb
ground_heuristics, ground_lazy_heuristic_facts
ground_facts, ground_lines
```

Le metriche vengono prodotte cosi':

```text
total_s                       Clingo JSON --outf=2 --stats=2, campo Time.Total
solving_s                     Clingo JSON, campo Time.Solve
grounding_s                   total_s - solving_s
choices                       Clingo JSON, Stats.Core.Choices
conflicts                     Clingo JSON, Stats.Core.Conflicts
restarts                      Clingo JSON, Stats.Core.Restarts
rules                         Clingo JSON, Stats.LP.Rules.Final
variables                     Clingo JSON, Stats.Problem.Variables
memory_mb                     resource.getrusage(RUSAGE_CHILDREN).ru_maxrss / 1024
                              salvata in MB nel CSV; log e grafici la mostrano in GB
ground_heuristics             conteggio righe "#heuristic" in clingo --text
ground_lazy_heuristic_facts   conteggio righe "__heuristic(" in clingo --text
ground_facts                  conteggio fatti ground in clingo --text
ground_lines                  numero totale righe in clingo --text
```

`status`, `failure_reason`, `exit_code` e `memory_limit_hit` servono al benchmark per capire se una variante e' andata in timeout, in errore o in limite memoria. I grafici ignorano queste colonne.

## Generare I Grafici

Dopo il benchmark:

```bash
cd test_folder
./generate_graphs.sh
```

Se `matplotlib`/`numpy` non sono installati nel Python di sistema:

```bash
python3 -m venv /tmp/clingo-graphs-venv
/tmp/clingo-graphs-venv/bin/python -m pip install -r test_folder/tools/requirements.txt
cd test_folder
PYTHON_BIN=/tmp/clingo-graphs-venv/bin/python ./generate_graphs.sh
```

Lo script esegue:

```bash
python3 tools/gen_graphs.py --reset
python3 tools/gen_graphs.py --type bsp
python3 tools/gen_graphs.py --type bsp --exclude bspga
```

`bspga` e' il selettore compatto della variante `ga`/`BSP_ga.lp`; la cartella `no_ga` serve quando `ga` schiaccia la scala dei grafici.

Grafici principali generati:

```text
total_time.png
grounding_time.png
solving_time.png
ground_heuristics.png
ground_lazy_heuristic_facts.png
combined_heuristics.png
ground_program_lines.png
ground_facts.png
memory_comparison.png         memoria in GB
choices_comparison.png
conflicts_comparison.png
restarts_comparison.png
variables_comparison.png
heuristic_expansion_factor.png
additional_ground_lines_vs_lazy.png
grounding_time_vs_heuristic_size.png
lazy_solving_overhead.png
```

I quattro grafici interpretativi finali sono anche accodati in
`benchmark_results.png`. `additional_ground_lines_vs_lazy.png` usa la
controparte lazy disponibile nel CSV come controllo, non una baseline separata
senza euristiche.

Nei grafici di conteggio dove curve identiche o quasi identiche si
sovrappongono (`ground_heuristics.png`,
`ground_lazy_heuristic_facts.png`, `combined_heuristics.png`,
`ground_facts.png`, `variables_comparison.png`), il generatore puo'
applicare piccoli offset verticali solo visuali. Gli offset sono dichiarati
nella figura e non rappresentano differenze nei valori misurati. I grafici di
tempo, memoria e statistiche di ricerca restano senza offset.

## Prossimi Test Appuntati

Fase 2, confronto principale Clingo:

```bash
TIMEOUT_SECONDS=120 REPEATS=1 N_START=10 N_END=100 N_STEP=10 \
BSP_VARIANTS="gc lc" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Fase 2, confronto Alpha:

```bash
TIMEOUT_SECONDS=120 REPEATS=1 N_START=10 N_END=100 N_STEP=10 \
BSP_VARIANTS="ga la" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Fase 2, confronto ausiliari:

```bash
TIMEOUT_SECONDS=120 REPEATS=1 N_START=10 N_END=80 N_STEP=10 \
BSP_VARIANTS="gc gc_aux la la_aux" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Fase 3, run finale comparativo:

```bash
TIMEOUT_SECONDS=300 REPEATS=3 N_START=10 N_END=70 N_STEP=10 \
BSP_VARIANTS="gc gc_aux ga la lc la_aux" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Se troppe varianti ground vanno in timeout o memoria, usa un massimo comune piu' basso:

```bash
TIMEOUT_SECONDS=300 REPEATS=3 N_START=10 N_END=50 N_STEP=10 \
BSP_VARIANTS="gc gc_aux ga la lc la_aux" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Run esteso solo lazy:

```bash
TIMEOUT_SECONDS=300 REPEATS=3 N_START=80 N_END=200 N_STEP=20 \
BSP_VARIANTS="la lc" \
bash test_folder/benchmarks/benchmark_bsp.sh
```
