# Riepilogo interventi e guida di validazione

## Cosa e stato modificato

1. Propagatore C++
   - `decide` non scansiona piu tutti i body attivi.
   - Ogni istanza lazy diventa un `CandidateState`.
   - I candidati validi sono mantenuti in una coda ordinata (`std::set`) per priorita, peso e literal.
   - `propagate` e `undo` aggiornano aggregati e candidati osservando body positivi, target, negativi e sorgenti aggregate.
   - Le espressioni aritmetiche restano valutate sull'AST interno gia tipizzato; la valutazione avviene quando il candidato viene aggiornato o rivalidato.

2. Converter Python
   - `tools/asp_heuristic_converter.py` usa `clingo.ast` per individuare direttive `#heuristic`, anche multilinea.
   - La conversione produce ancora le modalita `la`, `lc`, `aux`, `la-aux`.
   - Il parser legacy e stato rimosso: una direttiva non parseabile via AST ora fallisce esplicitamente.

3. Validazione semantica
   - Aggiunto `tools/validate_lazy_semantics.py`, che esegue baseline e lazy con `--outf=2` e confronta JSON di clingo.
   - Supporta confronto su `models`, `optimum` o solo `result`.
   - Per default ignora simboli interni con prefisso `__`, come i fatti `__heuristic(...)`; usa `--keep-internal` per debug.

4. Test e corner case
   - Aggiunti test C++ per gli stati aggregati e casi end-to-end del propagatore lazy.
   - Aggiunte istanze limite in `test_folder/instances/corner_cases`: dominio vuoto, UNSAT esplicito, scelta simmetrica.

## Validazione rapida

Ricompila il binario modificato:

```bash
cmake --build clingo-modified/build --target clingo -- -j2
```

Esegui i corner case semantici:

```bash
python3 test_folder/tools/validate_lazy_semantics.py \
  --baseline test_folder/instances/corner_cases/empty_domain_native.lp \
  --lazy test_folder/instances/corner_cases/empty_domain_lazy.lp \
  --instance test_folder/instances/corner_cases/instance_empty.lp \
  --models 0 --compare models -- --heuristic=Domain

python3 test_folder/tools/validate_lazy_semantics.py \
  --baseline test_folder/instances/corner_cases/unsat_native.lp \
  --lazy test_folder/instances/corner_cases/unsat_lazy.lp \
  --instance test_folder/instances/corner_cases/instance_empty.lp \
  --models 0 --compare result -- --heuristic=Domain

python3 test_folder/tools/validate_lazy_semantics.py \
  --baseline test_folder/instances/corner_cases/symmetric_native.lp \
  --lazy test_folder/instances/corner_cases/symmetric_lazy.lp \
  --instance test_folder/instances/corner_cases/instance_empty.lp \
  --models 0 --compare models -- --heuristic=Domain
```

## Test C++

La build locale principale ha `CLINGO_BUILD_TESTS=OFF`. Per compilare i test senza sporcare la build principale:

```bash
cmake -S clingo-modified -B /tmp/clingo-lazy-tests -G Ninja \
  -DCLINGO_BUILD_TESTS=ON \
  -DCLASP_BUILD_TESTS=OFF \
  -DLIB_POTASSCO_BUILD_TESTS=OFF

cmake --build /tmp/clingo-lazy-tests --target test_clingo -- -j2
/tmp/clingo-lazy-tests/bin/test_clingo "[heuristic]"
```

## Validazione su encoding reali

Rigenera gli encoding lazy PUP con il converter AST:

```bash
python3 test_folder/tools/asp_heuristic_converter.py \
  test_folder/encodings/PUP/PUP_double.lp --mode la \
  -o /tmp/PUP_double_lazy.lp --no-comments
```

Poi confronta baseline e lazy. Per istanze piccole puoi confrontare tutti i modelli; per istanze grandi conviene partire da `--compare result` o `--compare optimum`.

```bash
python3 test_folder/tools/validate_lazy_semantics.py \
  --baseline test_folder/encodings/PUP/PUP_double.lp \
  --lazy /tmp/PUP_double_lazy.lp \
  --instance test_folder/instances/PUP_instances/Double/double-20.lp \
  --models 1 --compare result -- --heuristic=Domain
```

Esempio BSP partendo dallo stesso encoding nativo e convertendolo al volo:

```bash
python3 test_folder/tools/asp_heuristic_converter.py \
  test_folder/encodings/BSP/BSP_gc.lp --mode la \
  -o /tmp/BSP_gc_lazy.lp --no-comments

python3 test_folder/tools/validate_lazy_semantics.py \
  --baseline test_folder/encodings/BSP/BSP_gc.lp \
  --lazy /tmp/BSP_gc_lazy.lp \
  --instance test_folder/instances/BSP_instances/BSP_range.lp \
  -c n=10 --models 0 --compare models -- --heuristic=Domain
```

Nota: `encodings/BSP/BSP_la.lp` contiene anche il vincolo sulla differenza delle somme, mentre `encodings/BSP/BSP_gc.lp` lo lascia commentato; non vanno confrontati come se fossero semanticamente identici.

## Note metodologiche

- La coda dei candidati risolve il collo di bottiglia principale di `decide` senza introdurre un memory pool prematuro.
- Le chiavi `AtomKey` basate su `std::vector<int>` restano un possibile hotspot, ma conviene ottimizzarle solo dopo profiling mirato: passare subito a chiavi flat cambia molte assunzioni di matching e rischia regressioni.
- Anche il memory pool per `AggregateState` e utile come passo successivo se i profili mostrano frammentazione o molte costruzioni dinamiche.
- La validazione semantica deve accompagnare ogni benchmark: tempo e memoria non bastano se non si controlla che baseline e lazy abbiano stesso risultato osservabile.
