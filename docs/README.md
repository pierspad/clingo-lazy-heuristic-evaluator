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

Questa sezione serve per ricordare come eseguire i benchmark del problema BSP.

Gli script principali sono:

```bash
test_folder/benchmarks/benchmark_bsp.sh
test_folder/benchmarks/benchmark_runner.py
test_folder/generate_graphs.sh
```

Il benchmark BSP esegue più varianti dell'encoding BSP, cambiando automaticamente il valore della costante `n`, il seed e la variante da testare.

I risultati vengono salvati in:

```bash
test_folder/results/bsp_results.csv
```

---

## Eseguire il benchmark BSP standard

Dalla root del repository:

```bash
bash test_folder/benchmarks/benchmark_bsp.sh
```

Di default vengono usati questi parametri:

```bash
TIMEOUT_SECONDS=600
MEM_LIMIT_BYTES=34359738368
REPEATS=3
N_START=10
N_END=70
N_STEP=10
BSP_VARIANTS="gc gc_aux ga la lc la_aux"
```

Quindi, di default, vengono testati:

```bash
n = 10, 20, 30, 40, 50, 60, 70
```

Per ogni valore di `n`, lo script esegue tutte le varianti attive e ripete ogni run 3 volte, usando seed diversi.

---

## Varianti BSP disponibili

Le varianti disponibili sono:

```bash
gc
gc_aux
ga
la
lc
la_aux
la_co
```

Significato sintetico:

```text
gc      = encoding nativo Clingo, con semantica Clingo
gc_aux  = encoding nativo Clingo con predicati ausiliari
ga      = encoding nativo ground-and-solve con semantica Alpha
la      = encoding lazy con semantica Alpha
lc      = encoding lazy con semantica Clingo
la_aux  = encoding lazy con predicati ausiliari
la_co   = encoding lazy con vincolo BSP ottimizzato/lineare
```

Attenzione: `la_co` esiste, ma non è inclusa nel benchmark di default.

---

## Scegliere quali varianti eseguire

Lo script non usa un parametro `--exclude`.

Per escludere una variante, bisogna specificare direttamente la lista delle varianti da eseguire tramite `BSP_VARIANTS`.

Per esempio, per escludere `ga`:

```bash
BSP_VARIANTS="gc gc_aux la lc la_aux" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Per eseguire solo le varianti lazy:

```bash
BSP_VARIANTS="la lc la_aux la_co" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Per confrontare solo `gc` e `lc`:

```bash
BSP_VARIANTS="gc lc" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Per includere anche `la_co`:

```bash
BSP_VARIANTS="gc gc_aux ga la lc la_aux la_co" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

---

## Cambiare il valore massimo di `n`

Il parametro `N_END` controlla il massimo valore di `n`.

Per eseguire il benchmark fino a `n=100`:

```bash
N_END=100 \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Per eseguire da `n=10` a `n=200` con passo 10:

```bash
N_START=10 \
N_END=200 \
N_STEP=10 \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Per fare un test rapido solo su pochi valori:

```bash
N_START=10 \
N_END=30 \
N_STEP=10 \
REPEATS=1 \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Questo esegue solo:

```bash
n = 10, 20, 30
```

con una sola ripetizione per variante.

---

## Cambiare il numero di ripetizioni

Il parametro `REPEATS` controlla quante volte viene ripetuta ogni combinazione di:

```text
variante + valore di n
```

Per una sola ripetizione:

```bash
REPEATS=1 \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Per 5 ripetizioni:

```bash
REPEATS=5 \
bash test_folder/benchmarks/benchmark_bsp.sh
```

---

## Cambiare il timeout massimo

Il parametro `TIMEOUT_SECONDS` controlla il tempo massimo di una singola run.

Di default è:

```bash
TIMEOUT_SECONDS=600
```

cioè 600 secondi.

Per usare un timeout di 120 secondi:

```bash
TIMEOUT_SECONDS=120 \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Per usare un timeout di 30 minuti:

```bash
TIMEOUT_SECONDS=1800 \
bash test_folder/benchmarks/benchmark_bsp.sh
```

---

## Cambiare il limite di memoria

Il parametro `MEM_LIMIT_BYTES` controlla il limite di memoria in byte.

Di default è:

```bash
MEM_LIMIT_BYTES=34359738368
```

cioè 32 GiB.

Per usare 16 GiB:

```bash
MEM_LIMIT_BYTES=$((16 * 1024 * 1024 * 1024)) \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Per usare 8 GiB:

```bash
MEM_LIMIT_BYTES=$((8 * 1024 * 1024 * 1024)) \
bash test_folder/benchmarks/benchmark_bsp.sh
```

---

## Esempio completo per benchmark veloce

Questo comando esegue un benchmark rapido, utile per controllare che tutto funzioni:

```bash
REPEATS=1 \
N_START=10 \
N_END=30 \
N_STEP=10 \
TIMEOUT_SECONDS=120 \
BSP_VARIANTS="gc lc la" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Questo testa:

```text
varianti: gc, lc, la
n:        10, 20, 30
repeat:   1
timeout:  120 secondi
```

---

## Esempio completo per benchmark più serio

```bash
REPEATS=3 \
N_START=10 \
N_END=100 \
N_STEP=10 \
TIMEOUT_SECONDS=600 \
MEM_LIMIT_BYTES=$((32 * 1024 * 1024 * 1024)) \
BSP_VARIANTS="gc gc_aux ga la lc la_aux la_co" \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Questo testa tutte le varianti BSP, inclusa `la_co`, fino a `n=100`.

---

## Usare un binario clingo specifico

Normalmente lo script cerca automaticamente il binario modificato in:

```bash
build/bin/clingo
clingo-modified/build/bin/clingo
```

Se però vuoi forzare un binario specifico, puoi usare `CLINGO_MOD`.

Esempio:

```bash
CLINGO_MOD=./clingo-modified/build/bin/clingo \
bash test_folder/benchmarks/benchmark_bsp.sh
```

Oppure:

```bash
CLINGO_MOD=/percorso/al/binario/clingo \
bash test_folder/benchmarks/benchmark_bsp.sh
```

---

## Eseguire una singola run manualmente

Lo script `benchmark_runner.py` esegue una singola run e aggiunge il risultato a un CSV.

Esempio con la variante `lc` e `n=50`:

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
  --timeout 600 \
  --memory-bytes $((32 * 1024 * 1024 * 1024)) \
  --domain-heuristic
```

Questo è utile quando vuoi testare una sola variante senza eseguire tutto il benchmark BSP.

---

## Cosa misura il benchmark

Il CSV prodotto contiene colonne come:

```text
n
variant
seed
solving_s
total_s
grounding_s
choices
conflicts
restarts
rules
variables
memory_mb
ground_heuristics
ground_lazy_heuristic_facts
ground_facts
ground_lines
```

Significato delle colonne principali:

```text
n                           valore della costante n
variant                     variante dell'encoding testata
seed                        seed usato da clingo
solving_s                   tempo di solving
total_s                     tempo totale
grounding_s                 tempo stimato di grounding
choices                     numero di choice del solver
conflicts                   numero di conflitti
restarts                    numero di restart
rules                       numero di regole finali
variables                   numero di variabili del problema
memory_mb                   memoria massima osservata
ground_heuristics           numero di direttive #heuristic dopo grounding
ground_lazy_heuristic_facts numero di fatti __heuristic(...) dopo grounding
ground_facts                numero di fatti ground
ground_lines                numero di linee prodotte da clingo --text
```

---

## Generare i grafici BSP

Dopo aver eseguito il benchmark e prodotto il CSV, puoi generare i grafici con:

```bash
cd test_folder
./generate_graphs.sh
```

Lo script `generate_graphs.sh` esegue:

```bash
python3 tools/gen_graphs.py --reset
python3 tools/gen_graphs.py --type bsp
python3 tools/gen_graphs.py --type bsp --exclude bspga
```

Quindi fa tre cose:

```text
1. resetta/cancella i grafici precedenti;
2. genera i grafici BSP completi;
3. genera anche una versione dei grafici BSP escludendo bspga.
```

La versione senza `bspga` è utile perché la variante `ga` può essere molto più lenta o molto più grande delle altre, rendendo i grafici difficili da leggere.

Nota: nello script di benchmark la variante si chiama `ga`, mentre nei grafici può comparire come `bspga`.

---

## Generare manualmente solo i grafici BSP

Da dentro `test_folder`:

```bash
python3 tools/gen_graphs.py --type bsp
```

Per generare i grafici BSP escludendo `bspga`:

```bash
python3 tools/gen_graphs.py --type bsp --exclude bspga
```

Per resettare i grafici precedenti:

```bash
python3 tools/gen_graphs.py --reset
```

---

## Workflow consigliato

Per un test veloce:

```bash
./test_folder/tools/recompile.sh

REPEATS=1 \
N_START=10 \
N_END=30 \
N_STEP=10 \
BSP_VARIANTS="gc lc la" \
bash test_folder/benchmarks/benchmark_bsp.sh

cd test_folder
./generate_graphs.sh
```

Per un benchmark più completo:

```bash
./test_folder/tools/recompile.sh

REPEATS=3 \
N_START=10 \
N_END=100 \
N_STEP=10 \
TIMEOUT_SECONDS=600 \
MEM_LIMIT_BYTES=$((32 * 1024 * 1024 * 1024)) \
BSP_VARIANTS="gc gc_aux ga la lc la_aux la_co" \
bash test_folder/benchmarks/benchmark_bsp.sh

cd test_folder
./generate_graphs.sh
```