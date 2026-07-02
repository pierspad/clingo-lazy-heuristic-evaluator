# Rapporto: grafici mancanti e riorganizzazione `test_folder/`

_Data: 29 giugno 2026 — suite "Lazy Heuristics / Dynamic Aggregates"._

## 1. Cosa è stato fatto

### 1.1 Riorganizzazione della cartella

La macchina del **benchmark-tool** (`btool`) è stata raccolta in una sola
sottocartella, `test_folder/benchmark_folder_clingo/`. In `test_folder/`, fuori
dalla sottocartella, restano solo gli ingredienti concettuali e gli output dei
grafici:

```
test_folder/
├─ encodings-native/      (invariato)
├─ encodings-prolog/      (invariato)
├─ instances/             (invariato)
├─ legacy/                (invariato — vecchia suite + gen_graphs.py)
├─ INTENT.txt
├─ graphs-native/                       ← prodotti dalla full
├─ graphs-prolog/                        ← prodotti dalla full
├─ graphs-comparison-native-prolog/      ← prodotti dalla full
└─ benchmark_folder_clingo/
   ├─ programs/  templates/  resultparsers/  runscripts/  scripts/
   ├─ benchmarks/  tools/  .venv/  requirements.txt  README-benchmark-tool.md
   └─ output/  results.xml  results.xlsx   (generati da btool)
```

I due script entry `1_run_benchmark_short.sh` e `2_run_benchmark_full.sh`
**restano nella root del repo** (come richiesto); puntano internamente a
`benchmark_folder_clingo/`.

**Conseguenza tecnica.** Il working dir di `btool` è ora
`benchmark_folder_clingo/`: tutte le sue convenzioni (`resultparsers/`,
`programs/`, `{root}`, `output/`) si risolvono dentro la sottocartella in modo
naturale; gli unici riferimenti "verso l'alto" sono gli encoding, ora
`../encodings-native/...` nel runscript, e i tre alberi di grafici, scritti in
`../graphs-*` (cioè in `test_folder/`).

> **Da verificare al primo run reale:** che `btool gen` risolva correttamente i
> path `../encodings-*` (dipende dalla versione di benchmark-tool). È l'unico
> punto non testabile a freddo, perché richiede i binari clingo compilati.

### 1.2 Grafici reintegrati

Il vecchio `tools/plot_results.py` produceva **solo 3 metriche** (`solving`,
`mem`, `decide_calls`), per giunta mischiando i due backend sugli stessi assi e
scrivendo in una cartella piatta `graphs/`. Da qui i molti grafici mancanti che
avevi notato rispetto alla vecchia suite (`legacy/gen_graphs.py`).

Il nuovo `plot_results.py` ricostruisce l'intero set, separato per backend e per
famiglia, con il theming per-variante della vecchia suite, e aggiunge l'albero
di confronto con il **verdetto** native-vs-prolog.

## 2. Inventario: cosa mancava e cosa c'è ora

Legenda stato: ✅ reintegrato · ✅* reintegrato ma richiede `ground_counts.csv`
(passo `tools/ground_counts.py`, disaccoppiato dal cronometraggio) · 🆕 nuovo ·
⚠️ non portato (motivo indicato).

| # | Grafico (vecchia suite) | Sorgente dato | Prima (btool) | Ora |
|---|---|---|---|---|
| 1 | Solving Time | `solving` | presente | ✅ |
| 2 | Grounding Time | `grounding` | mancante | ✅ |
| 3 | Total Time | `clingo_total` | mancante | ✅ |
| 4 | Peak RSS Memory (GB) | `mem` | presente (mischiato) | ✅ separato per backend |
| 5 | Choices | `choices` | mancante | ✅ |
| 6 | Conflicts | `conflicts` | mancante | ✅ |
| 7 | Restarts | `restarts` | mancante | ✅ |
| 8 | Solver Rules | `rules` | mancante | ✅ |
| 9 | Solver Variables | `variables` | mancante | ✅ |
| 10 | Solving Cost per Choice | derivato `1000·solving/choices` | mancante | ✅ |
| 11 | Decide Calls (propagatore) | `decide_calls` | presente (mischiato) | ✅ solo prolog/lazy |
| 12 | Total Prolog Query Time | `total_prolog_query_time_ms` | mancante | ✅ solo lazy |
| 13 | Prolog Cost per Decision | derivato `query_ms/decide_calls` | mancante | ✅ solo lazy |
| 14 | Lazy/Standard Solving Ratio | derivato (coppie gc/lc, ga/la) | mancante | ✅ |
| 15 | Dashboard multi-pannello | aggregato | mancante | ✅ `_dashboard.png` |
| 16 | Ground #heuristic directives | `ground_counts.csv` | mancante | ✅* |
| 17 | Ground `__heuristic` facts | `ground_counts.csv` | mancante | ✅* |
| 18 | Combined heuristics | `ground_counts.csv` | mancante | ✅* |
| 19 | Ground Program Lines | `ground_counts.csv` | mancante | ✅* |
| 20 | Grounding Time vs Heuristic Size (scatter) | xml + `ground_counts.csv` | mancante | ✅* |
| 21 | Confronto native-vs-prolog (albero) | `xml` | mancante | ✅ `graphs-comparison-native-prolog/` |
| 22 | **Verdetto per area** (tabella migliore) | `xml` | — | 🆕 `_verdict.png` |
| 23 | Random Search Variability (multi-seed) | CSV multi-seed | mancante | ⚠️ vedi §4 |

## 3. Struttura degli alberi prodotti

Per ciascun albero, una sottocartella per famiglia (`1_BSP/`, `2_PUP/`, `3_HRP/`):

- `graphs-native/<fam>/` — tutte le varianti, backend native (grafici 1–10, 14, 15; 16–20 con `ground_counts.csv`).
- `graphs-prolog/<fam>/` — come sopra + 11, 12, 13 (metriche del propagatore, definite solo qui).
- `graphs-comparison-native-prolog/<fam>/` — `solving`, `grounding`, `clingo_total`, `mem`, `decide_calls`, `prolog_ms_per_decide` con curve native (linea piena) vs prolog (tratteggio), più `_verdict.png` che **decreta il migliore per area** all'ultima taglia comune risolta.

Il confronto si concentra sulle varianti **lazy** (`la`, `lc`, + BSP `la_aux`,
`la_co`) con il baseline `gc`: è lì che i due backend divergono davvero (il
native usa il propagatore C++, il prolog il motore SWI-Prolog in-process); sulle
`g*` i due backend coincidono per costruzione.

## 4. Cosa resta genuinamente mancante (e perché)

**Grafici di variabilità multi-seed** (`random_variability`). La vecchia suite
li produceva da CSV con colonna `seed`/`setting` e opzioni randomizzate di
clingo. Il runscript attuale gira con `runs="1"` e **nessuno sweep di seed**:
`results.xml` non ha la dimensione seed, quindi questi grafici non sono
producibili così com'è. Per reintegrarli servirebbe aggiungere al runscript un
setting con più run seed-ati (es. `--seed` + `runs="K"`) e poi un ramo dedicato
nel plotter. **Non l'ho fatto** perché cambia il disegno sperimentale (più che
"un grafico", è una campagna di run aggiuntiva): da decidere se ti serve per la
tesi.

**Metriche extra ora aggiunte** (erano in `results.xml` ma non graficate). Sono
prodotte come singoli PNG e **accodate in fondo al dashboard generale**
(`_dashboard.png`), sotto un separatore "metriche aggiuntive":

- generali (entrambi i backend): `atoms`, `constraints` (dimensione strutturale,
  come rules/variables) e `time` = wall-clock di runlim, da leggere accanto a
  `clingo_total` (il primo include overhead di processo/IO, il secondo è il tempo
  interno a clingo);
- anatomia del costo per-decisione del propagatore lazy (solo prolog):
  `total_decide_time_ms` e le sue componenti `total_state_sync_time_ms`,
  `total_candidate_scan_time_ms`, `total_literal_lookup_time_ms`,
  `total_candidate_selection_time_ms` (decide ≈ sync + query + scan + lookup +
  selection), più `total_candidates_seen` e `avg_candidates_per_decide` (quanto
  lavoro vede il propagatore a ogni decisione).

Restano fuori solo `models` (sempre 1 con `-n 1`), `max_candidates_seen` e il
flag testuale `lazy_active` (non è una curva: è la sanity "l'euristica lazy ha
deciso davvero?"). Aggiungerne altre è una riga ciascuna in `EXTRA_METRICS`.

## 5. Come si rigenerano

```bash
# dalla root del repo
sh 2_run_benchmark_full.sh          # esegue tutto e produce i tre alberi in test_folder/

# (opzionale) per i grafici di grounding 16–20, prima:
cd test_folder/benchmark_folder_clingo && source .venv/bin/activate
python3 tools/ground_counts.py      # -> output/ground_counts.csv
# poi la full li include automaticamente (bench_common.sh lo passa se presente)
```

Il verdetto per area viene anche stampato a terminale a fine run.
