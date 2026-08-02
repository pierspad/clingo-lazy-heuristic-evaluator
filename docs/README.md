# clingo-lazy-heuristics

Due versioni modificate di clingo che valutano le euristiche di dominio **lazy**, cioè a
runtime nel propagatore, invece di groundarle come direttive `#heuristic`:

- **`clingo-native/`** — DSL nativo: fatti `__heuristic(...)`, valutati in C++.
  Sintassi: [euristiche-native-sintassi.md](euristiche-native-sintassi.md).
- **`clingo-prolog/`** — regole come stringhe `heuristic("...")`, valutate da SWI-Prolog o da
  un programma ASP ausiliario. Sintassi: [euristiche-prolog-sintassi.md](euristiche-prolog-sintassi.md).

Entrambi implementano `Clingo::Heuristic` (propagatore + callback `decide`) e vanno lanciati
con `--heuristic=Domain`. L'euristica non cambia mai l'insieme delle risposte, solo l'ordine di
esplorazione.

## Struttura

```text
clingo-native/          clingo con il propagatore __heuristic
clingo-prolog/          clingo con il propagatore heuristic("...")
compile_all.sh          build delle due versioni + SWI-Prolog (HPC, via sbatch)
compile_all_local.sh    stessa build in locale, incrementale
N_run_benchmark_*.sh    pipeline di benchmark (vedi sotto)
test_folder/            encoding, istanze e macchina di benchmark
  encodings-native/     encoding con __heuristic     (BSP, PUP, HRP)
  encodings-prolog/     encoding con heuristic("...")(BSP, PUP, HRP)
  encodings-alpha/      encoding per il solver ALPHA
  instances/            istanze BSP / PUP / HRP + corner case
  benchmark_folder_clingo/   benchmark-tool: runscript, template, parser, plot
ALPHA/                  solver ALPHA (riferimento esterno)
thesis/, paper/         tesi LaTeX e bibliografia
clingo_hpc_graphs/      risultati e grafici scaricati dall'HPC
```

## Build

Richiede i sorgenti di SWI-Prolog 10 in `../swipl-moderno/` (`../swipl-moderno/download.sh`).

```bash
./compile_all_local.sh
```

Compila SWI-Prolog (in `$HOME/swipl-10`) e i due clingo in `clingo-native/build` e
`clingo-prolog/build` — gli stessi path che gli script di benchmark si aspettano. La build è
incrementale; `CLEAN_BUILD=1` forza una ricompilazione pulita. Su HPC si usa `compile_all.sh`
(via `sbatch`, con i moduli Spack).

## Benchmark

Gli script numerati in root sono la pipeline completa; ognuno ha in testa un header con
parametri e dettagli.

| Script | Cosa fa |
|---|---|
| `1_run_benchmark_short.sh` | smoke test locale: mini-subset di istanze, timeout 15s, grafici di prova |
| `2_run_benchmark_full.sh` | suite completa in locale (BSP 10..200, PUP 20..200, HRP 2..20, timeout 600s) |
| `3_run_benchmark_short_hpc.sh` | smoke test su SLURM |
| `4_run_benchmark_hpc.sh` | suite completa distribuita su SLURM |
| `5_evaluate_hpc.sh` | estrae `results.xml` dai run finiti e delega la Fase 4 a `6_...` |
| `6_plot_graphs_hpc.sh` | grafici; su HPC un job SLURM per figura, in locale in sequenza |

Tutti sono idempotenti: i run già completati vengono saltati, `FORCE=1` rifà tutto. `3_` e `4_`
si rilanciano da soli su un compute node via `srun` se invocati dal login node (compilare sul
login node produce binari linkati alla glibc sbagliata).

`bench-runs-local/` contiene copie degli stessi script con `REPO_ROOT` risalito di un livello,
per lanciarli da lì in locale; non vengono mai sincronizzate verso l'HPC.

## Varianti degli encoding

Ogni variante esiste sia in `encodings-native/` che in `encodings-prolog/` con lo stesso nome, e
sono i `<setting>` di `test_folder/benchmark_folder_clingo/runscripts/runscript.xml`.

| Variante | Descrizione |
|---|---|
| `gc_noheur` | ground-and-solve senza euristica — baseline |
| `gc` | ground, `#heuristic` con `#sum` (semantica Clingo) |
| `ga` | ground, semantica Alpha (aggregato materializzato con `sum_value/1`) |
| `ga_weak` | come `gc` ma senza il letterale negato nel corpo: approssimazione "debole" di Alpha (solo BSP) |
| `lc` | lazy, semantica Clingo |
| `la` | lazy, semantica Alpha |
| `la_aux` | lazy Alpha con l'aggregato precalcolato in un predicato ausiliario (solo BSP) |
| `la_co` | lazy Alpha con vincolo BSP lineare (solo BSP) |

## Risultati e grafici

I run scrivono in `test_folder/benchmark_folder_clingo/` (`results.xml`, `output/`); i grafici
finiscono in `test_folder/graphs-native/`, `graphs-prolog/`,
`graphs-comparison-native-prolog/` e `riassunto_grafici/`.

Per rigenerare i grafici da dati già raccolti, senza rifare i run:

```bash
sh 6_plot_graphs_hpc.sh --results FILE.xml --out-base DIR
```

`tools/plot_results.py --list-jobs` elenca i job disponibili; `--only <job>` ne esegue uno solo.

## Sync con l'HPC

`hpc_sync_functions.zsh` definisce due funzioni zsh (da `source`are in `~/.zshrc`):

- `pushhpccode` — invia il codice all'HPC (esclude sé stesso, `compile_all_local.sh`,
  `bench-runs-local/` e i binari compilati);
- `copyhpcgraphs` — scarica grafici, `results.xml`, log ed `xlsx` in `clingo_hpc_graphs/`.

`wait_hpc.sh` attende che `squeue` sia vuota prima di lanciare `5_evaluate_hpc.sh`;
`stop_hpc.sh` cancella i job dell'utente (`-b` solo quelli della campagna benchmark, `-y` senza
conferma).

## Variabili d'ambiente dei propagatori

| Variabile | Effetto |
|---|---|
| `LAZY_HEURISTIC_BACKEND=prolog` | in `clingo-prolog`, usa SWI-Prolog invece del backend ASP ausiliario |
| `LAZY_HEURISTIC_STATS=1` | riepilogo del propagatore su stderr (`LAZY_PROLOG_STATS` è l'alias accettato) |
| `LAZY_HEURISTIC_DEBUG=1` | log diagnostici (regole raccolte, programma ausiliario, decisioni) |
| `LAZY_PROLOG_RANKING=clingo-like` | variante di ranking: prima il migliore per target, poi ordine globale |

## Utilità

- `test_folder/benchmark_folder_clingo/tools/gen_bsp_instances.py`, `gen_hrp_instances.py` — generano le istanze.
- `tools/ground_counts.py` — conta direttive `#heuristic` e fatti lazy nel programma ground.
- `tools/check_equivalence.py` — verifica che le varianti diano le stesse risposte.
- `verify_flattening_equivalence.sh` — confronta choices/conflicts fra working tree e `HEAD`.
