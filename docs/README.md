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

Richiede i sorgenti di SWI-Prolog 10 in `../swipl-moderno/` (`../swipl-moderno/download.sh`) e
un **JDK** (serve `javac`, non basta il runtime).

```bash
./compile_all_local.sh
```

Compila SWI-Prolog (in `$HOME/swipl-10`) e i due clingo in `clingo-native/build` e
`clingo-prolog/build` — gli stessi path che gli script di benchmark si aspettano. La build è
incrementale; `CLEAN_BUILD=1` forza una ricompilazione pulita. Su HPC si usa `compile_all.sh`
(via `sbatch`, con i moduli Spack), che compila anche il solver Alpha.

**SWI-Prolog va costruito con JPL**: il solver Alpha usato come riferimento esterno valuta le
euristiche come query Prolog e senza `jpl.jar`/`libjpl.so` non compila. Per questo `download.sh`
prende il tarball completo di swi-prolog.org e non l'archive di GitHub, dove `packages/` sono
submodule non espansi (directory vuote, e nessun package viene costruito senza che nulla lo
segnali).

La selezione avviene con `-DSWIPL_PACKAGE_LIST=jpl`, **non** con i flag di gruppo
`-DSWIPL_PACKAGES_<GRUPPO>=OFF`. Quei flag non bastano: `cmake/PackageSelection.cmake` dichiara
`SWIPL_PKG_DEPS_http = clib sgml json ssl` e `http` sta nel gruppo BASIC, quindi `ssl` e `json`
vengono ritirati dentro come dipendenze mentre `SWIPL_PACKAGES_SSL=OFF` resta scritto in
`CMakeCache.txt` senza alcun effetto. Sul cluster è costato una build morta a 1023/1025 sui
certificati di *test* di openssl (`openssl.cnf` assente nel prefix Spack), con `jpl.jar` già
costruito ma `ninja install` mai eseguito. Con la lista esplicita i target passano da ~1025 a
~349 e la superficie di fallimento sparisce.

**Il cluster kr non ha alcun modulo java** (`module avail` elenca solo toolchain C/C++, verificato
il 2026-08-03), quindi il JDK va scompattato in `$HOME` una volta sola:

```bash
sh get_jdk.sh
```

Scarica Eclipse Temurin 21 (versione pinnata, sha256 verificato) in `$HOME/jdk-21`, senza root e
senza package manager. `compile_all.sh` cerca `$HOME/jdk-*` da solo; in alternativa si può
passare un JDK già presente altrove:

Lo **stesso** JDK serve anche a *runtime*, non solo alla build: `jpl.jar` viene compilato da
`javac` senza `-target`, quindi porta i class file della versione del JDK che l'ha costruito, e
una JVM più vecchia lo rifiuta con `UnsupportedClassVersionError` (sul login node del cluster
`java` è l'11, contro un `jpl.jar` compilato con il 21). Per questo `programs/alpha-qh-1.0`
risolve la JVM con lo stesso ordine di precedenza — `JAVA_HOME`, poi `$HOME/jdk-*`, poi `java`
in PATH — invece di fidarsi del PATH, e `ALPHA_JAVA` permette di forzarla.

```bash
sbatch --export=ALL,JAVA_HOME=/percorso/al/jdk compile_all.sh
```

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

`get_jdk.sh` non fa parte della pipeline: è un passo di setup una-tantum, vedi *Build*.

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

### Il solver Alpha come riferimento esterno

Oltre ai due backend del propagatore, `runscript.xml` definisce un terzo `<system>`,
`alpha-qh`, che **non fa parte della matrice**: è il solver lazy-grounding dei paper
Comploi-Taupe, usato per rispondere a "quanto costa ottenere la semantica ad aggregati dinamici
dentro clingo, rispetto a prenderla da chi la implementa nativamente".

| Setting | Descrizione |
|---|---|
| `alpha` | encoding dei paper con `-uqh` (euristiche valutate come query Prolog) |
| `alpha_noheur` | stesso encoding con `-ids`: baseline interno, sta ad `alpha` come `gc_noheur` sta a `gc` |

Solo su BSP e PUP: per HRP non esiste un encoding Alpha degli autori, e tradurne uno a mano
introdurrebbe una variabile in più proprio nel confronto fra sistemi. Gli encoding in
`encodings-alpha/` sono copiati **tali e quali** da `ALPHA/Evaluation/`, e le istanze PUP della
suite sono byte-identiche a quelle del supplementary material.

Due avvertenze che valgono ogni volta che si leggono quei numeri:

- serve la variante **Qh** (`-uqh`). Il branch upstream `domspec_heuristics_extended` accetta la
  stessa sintassi ma valuta l'aggregato staticamente: su BSP l'euristica non bilancia nulla
  (tutto finisce in `b`) e i backtrack esplodono. La release ufficiale 0.7.0 non supporta
  affatto `#heuristic`;
- Alpha gira su JVM: il picco di RSS misurato da runlim include l'heap **riservato** (`-Xmx`,
  fissato dal wrapper sotto il memout). Confrontabili fra i due sistemi sono solo le misure
  esterne di runlim — wall-clock e RSS — non i contatori interni, che contano fenomeni diversi.

## Risultati e grafici

I run scrivono in `test_folder/benchmark_folder_clingo/` (`results.xml`, `output/`); i grafici
finiscono in `test_folder/graphs-native/`, `graphs-prolog/`,
`graphs-comparison-native-prolog/`, `graphs-comparison-clingo-alpha/` e `riassunto_grafici/`.

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
