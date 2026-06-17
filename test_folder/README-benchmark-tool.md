# Suite di benchmark con `benchmark-tool` (potassco)

Questa cartella usa [`benchmark-tool`](https://github.com/potassco/benchmark-tool)
(CLI `btool`, v2.x) come runner canonico per lo studio "Lazy Heuristics /
Dynamic Aggregates". Sostituisce i vecchi script bash + `benchmark_runner.py`,
ora archiviati in `legacy/`.

Funziona **in locale** (esecuzione sequenziale) e **su cluster SLURM**
(esecuzione distribuita) dallo stesso runscript.

---

## 1. Mappa concettuale → componenti benchmark-tool

| Asse dello studio | Componente benchmark-tool | Valori |
|---|---|---|
| **backend** | `system` | `clingo-native`, `clingo-prolog` |
| **variante** (approccio + semantica) | `setting` | `gc`, `gc_noheur`, `ga`, `la`, `lc` (+ BSP-only: `ga_weak`, `la_aux`, `la_co`) |
| **famiglia** | `benchmark` | `BSP`, `PUP`, `HRP` |

Convenzioni varianti: prima lettera = approccio (`g*` ground-and-solve, `l*`
lazy/dynamic-aggregates); ultima lettera = semantica (`*c` clingo-like, `*a`
alpha-like).

**Come si combinano gli encoding.** Ogni `setting` porta uno o più `<encoding>`
taggati per famiglia (`encoding_tag="bsp|pup|hrp"`); ogni `<folder>` di
benchmark ha lo stesso `encoding_tag`. Così la variante `gc` usa
`BSP_gc.lp` sui BSP, `PUP_gc.lp` sui PUP, ecc. L'attributo `tag` del setting
indica invece a **quali famiglie** la variante si applica: le varianti
BSP-only hanno `tag="bsp"` e non girano su PUP/HRP. I `runtag` selezionano i
setting per famiglia.

Entrambi i `system` vengono eseguiti automaticamente da ogni `runtag` (il
runtag non fissa il system): `clingo-native` usa `encodings-native/`,
`clingo-prolog` usa `encodings-prolog/`.

---

## 2. Struttura della cartella

```
test_folder/
├─ runscripts/runscript.xml     # definizione completa (locale + cluster)
├─ programs/
│  ├─ clingo-native-1.0         # wrapper system backend native
│  ├─ clingo-prolog-1.0         # wrapper system backend prolog (env propagatore)
│  ├─ runlim                    # limitatore tempo/memoria (binario, NON in git)
│  └─ gcat.sh                   # helper di benchmark-tool
├─ templates/
│  ├─ seq-generic.sh            # template di run (PATCHATO: cattura anche stderr)
│  └─ single.dist              # template SLURM (#SBATCH)
├─ resultparsers/clasp.py       # resultparser CUSTOM (vedi §6)
├─ benchmarks/                  # istanze pulite, una classe per famiglia
│  ├─ BSP/  bsp-0003.lp ...     # generate (#const n=N) da tools/gen_bsp_instances.py
│  ├─ PUP/  double-*.asp        # copiate da instances/PUP_instances/Double
│  └─ HRP/  house-*.asp         # copiate da instances/HRP_instances (no sanity)
├─ encodings-native/  encodings-prolog/   # invariati
├─ tools/
│  ├─ gen_bsp_instances.py      # rigenera le istanze BSP parametriche
│  ├─ plot_results.py           # grafici da results.xml
│  └─ ground_counts.py          # conteggi grounding (disaccoppiati, vedi §7)
├─ output/                      # generato da `btool gen` (NON in git)
└─ legacy/                      # vecchi script bash + benchmark_runner.py
```

---

## 3. Prerequisiti

```bash
cd test_folder
source .venv/bin/activate
pip install potassco-benchmark-tool        # fornisce `btool`
```

**`runlim`** (limitatore usato dal template di run) va compilato e messo in
`programs/runlim`:

```bash
git clone https://github.com/arminbiere/runlim /tmp/runlim
cd /tmp/runlim && ./configure.sh && make
cp runlim <repo>/test_folder/programs/runlim
```

**Binari clingo.** I wrapper cercano i binari via variabile d'ambiente, con
default ai build locali del repo:

```bash
export CLINGO_NATIVE_BIN=/percorso/clingo-native/build/bin/clingo
export CLINGO_PROLOG_BIN=/percorso/clingo-prolog/build/bin/clingo
```

Il wrapper prolog imposta da sé `LAZY_HEURISTIC_BACKEND=prolog` (attiva il
motore SWI-Prolog query-driven) e `LAZY_PROLOG_STATS=1` (emette la riga
`[lazy-prolog] summary ...` da cui il parser estrae `decide_calls` & co.).

---

## 4. Workflow LOCALE

```bash
cd test_folder
source .venv/bin/activate

# (ri)genera le istanze BSP se cambi il range
python3 tools/gen_bsp_instances.py            # default n=3..30 step 1

# 1) genera gli script di run (pulendo l'output precedente)
btool gen -c runscripts/runscript.xml

# 2) esegui lo studio locale (sequenziale). start.py fa da sé chdir alla
#    propria cartella: vai lanciato con un percorso che includa la directory.
python3 output/study-local/local/start.py     # esegue tutti i run del progetto

# 3) raccogli i risultati -> results.xml (TUTTE le misure)
btool eval runscripts/runscript.xml > results.xml

# 4a) foglio di calcolo navigabile (tutte le misure, con grafici)
btool conv -m all -o output/results.xlsx results.xml

# 4b) grafici per famiglia/misura
python3 tools/plot_results.py --machine local --measures solving mem decide_calls
#     -> graphs/<FAM>_<measure>_local.png
```

> Nota: `start.py` salta i run già completati (file `.finished`). Per rieseguire
> da zero usa `btool gen -c` (pulisce `output/`).

---

## 5. Workflow CLUSTER (SLURM)

Sul cluster, dopo aver clonato il repo e attivato l'ambiente:

```bash
# ricompila runlim sul cluster (binario platform-specific) -> programs/runlim
# imposta i binari clingo del cluster
export CLINGO_NATIVE_BIN=...; export CLINGO_PROLOG_BIN=...

# genera gli script (crea i .dist SLURM in output/study-hpc/hpc/)
btool gen -c runscripts/runscript.xml

# dispaccia i job distribuiti
btool run-dist output/study-hpc/hpc          # oppure: sbatch output/study-hpc/hpc/start*.dist

# a job conclusi, stessa raccolta del flusso locale
btool eval runscripts/runscript.xml > results.xml
btool conv -m all -o output/results.xlsx results.xml
python3 tools/plot_results.py --machine hpc
```

Parametri SLURM nel `<distjob name="dist-hpc" ...>` del runscript:
`timeout`, `memout` (MB), `walltime`, `cpt` (cpus-per-task), `partition`
(**default `kr`: cambialo con quello del tuo cluster**), `script_mode="timeout"`
(raggruppa i run sotto la walltime). Opzioni SBATCH extra per-setting via
`dist_options`.

`verify` ricontrolla gli errori di runlim e ri-genera i run falliti:
```bash
btool verify runscripts/runscript.xml
```

---

## 6. Resultparser custom (`resultparsers/clasp.py`)

Selezionato da `measures="clasp"` sui system; sovrascrive il parser di default.
Oltre alle statistiche standard (status, `time` = wall di runlim, `mem` = picco
di runlim, models/choices/conflicts/restarts, error/timeout/memout) aggiunge:

- `clingo_total`, `solving`, `grounding` — da `Time: total (Solving: ...)`;
  `grounding = total − solving`.
- `rules`, `variables`, `atoms`, `constraints` — conteggi strutturali clingo.
- metriche del propagatore prolog dalla riga `[lazy-prolog] summary`:
  `decide_calls`, `total_decide_time_ms`, `total_state_sync_time_ms`,
  `total_prolog_query_time_ms`, `total_candidate_scan_time_ms`,
  `total_literal_lookup_time_ms`, `total_candidate_selection_time_ms`,
  `total_candidates_seen`, `max_candidates_seen`, `avg_candidates_per_decide`.
- `lazy_active` — **flag di sanity**: per variante `l*` su backend prolog vale
  `active` se `decide_calls > 0`, `inactive` se l'euristica non ha mai deciso
  (fallback silenzioso da intercettare).

> **Perché serve `2>&1` nel template.** La riga `summary` del propagatore va su
> **stderr**; il template `seq-generic.sh` è stato patchato per redirigere
> `}} > runsolver.solver 2>&1`, così tutto l'output del solver finisce nel file
> che il parser legge. Senza la patch le metriche del propagatore andrebbero
> perse.

La **memoria di picco** (`mem`) è misurata sull'unico processo clingo che
grounda **e** risolve: cattura quindi anche l'esplosione di grounding delle
varianti `g*`, fenomeno centrale della tesi.

---

## 7. Conteggi di grounding (disaccoppiati)

```bash
python3 tools/ground_counts.py                 # -> output/ground_counts.csv
python3 tools/ground_counts.py --families BSP --backends native
```

Conta, via `clingo --text`, quante euristiche/fatti vengono materializzati dal
grounder (`ground_heuristics`, `ground_lazy_heuristic_facts`,
`ground_prolog_heuristic_facts`, `ground_facts`, `ground_lines`).

È **separato** dal benchmark cronometrato perché stampare l'intero programma
ground è pesantissimo in memoria per le `g*` a n grande: misurarlo nello
stesso processo falserebbe `mem`. Esempio (BSP, n=30): `gc` materializza
~28 000 direttive `#heuristic`, `la` solo 2 fatti-template `__heuristic` →
l'esplosione combinatoria vs il risparmio lazy. Attenzione: i conteggi lazy
**sottostimano** il lavoro runtime (un template genera N candidati a runtime,
fuori dal grounder); il lavoro reale si legge su `decide_calls` /
`total_decide_time_ms`.

---

## 8. Personalizzazioni rapide

- **Range BSP**: `python3 tools/gen_bsp_instances.py --start 40 --end 100 --step 10 --clean`.
- **Timeout / memoria**: attributi `timeout` (s) e `memout` (MB) di
  `<seqjob>` / `<distjob>` nel runscript.
- **Timeout per-famiglia diversi**: definisci più `seqjob`/`distjob` e più
  `project`, uno per famiglia (un solo `runtag` ciascuno).
- **Nuove istanze**: aggiungi i file in `benchmarks/<FAM>/` (per BSP rigenera).
- **Nuove varianti**: aggiungi gli encoding in `encodings-*/` e un `<setting>`
  in **entrambi** i system, con i giusti `encoding_tag` e `tag`.
- **Parallelismo locale**: attributo `parallel` di `<seqjob>` (default 1 per
  misure di tempo pulite).
