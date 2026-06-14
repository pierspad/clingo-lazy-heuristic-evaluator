"""
DESCRIZIONE E ORIGINE DEI DATI DEI GRAFICI
==========================================
Questo script genera grafici PNG a partire dai CSV per-backend prodotti dai
benchmark. Il layout dei dati e' uno per backend:

    test_folder/results-native/1_BSP_native.csv
    test_folder/results-native/2_PUP_native.csv
    test_folder/results-prolog/1_BSP_prolog.csv
    test_folder/results-prolog/2_PUP_prolog.csv
    test_folder/results-<backend>/1_BSP_<backend>_random.csv   (multi-seed)

I grafici vengono scritti in tre alberi distinti:

    test_folder/graphs-native/{1_BSP,2_PUP}/         tutte le varianti, backend native
    test_folder/graphs-prolog/{1_BSP,2_PUP}/         tutte le varianti, backend prolog
    test_folder/graphs-native-prolog/{1_BSP,2_PUP}/  confronto native vs prolog,
                                                     solo varianti lazy

I CSV vengono prodotti da:

    test_folder/benchmarks/0_benchmark.sh  (orchestratore)
    test_folder/benchmarks/{1,2}_{native,prolog}_{bsp,pup}.sh
    test_folder/benchmarks/benchmark_runner.py

Il generatore grafici non riesegue Clingo: legge le colonne numeriche gia'
presenti nel CSV, calcola solo metriche derivate esplicite, raggruppa per
(variant, n), calcola media e deviazione standard sui seed, e disegna le curve.
Se nel CSV e' presente la colonna `setting`, genera anche grafici dedicati alla
variabilita' tra seed e opzioni randomizzate di Clingo.

Origine esatta delle colonne usate nei grafici BSP
--------------------------------------------------

1. total_s
   - Comando sorgente: benchmark_runner.py esegue Clingo con
     `--outf=2 --stats=2`.
   - Campo JSON letto: `Time.Total`.

2. solving_s
   - Comando sorgente: stesso run JSON di Clingo.
   - Campo JSON letto: `Time.Solve`.

3. grounding_s
   - Comando sorgente: stesso run JSON di Clingo.
   - Calcolo in benchmark_runner.py: `Time.Total - Time.Solve`, troncato a 0
     se serve per evitare piccoli valori negativi da arrotondamento. E' una
     metrica derivata dalle statistiche JSON, non un tempo di grounding puro.

4. choices, conflicts, restarts
   - Comando sorgente: stesso run JSON di Clingo.
   - Campi JSON letti:
     `Stats.Core.Choices`, `Stats.Core.Conflicts`, `Stats.Core.Restarts`.

5. rules
   - Comando sorgente: stesso run JSON di Clingo.
   - Campo JSON letto: `Stats.LP.Rules.Final`.

6. variables
   - Comando sorgente: stesso run JSON di Clingo.
   - Campo JSON letto: `Stats.Problem.Variables`.

7. memory_mb
   - Comando sorgente: processo Clingo lanciato da benchmark_runner.py.
   - Misura: `resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024`.
     Su Linux `ru_maxrss` e' in KiB, quindi il valore salvato nel CSV e' in MB.
   - SIGNIFICATO ONESTO DELLA MISURA: e' il picco RSS *end-to-end* dell'intero
     processo solver (grounding + search + propagatore custom), non la memoria
     del solo grounding. Per le varianti lazy (la, lc, la_aux, la_co) SWI-Prolog
     gira in-process nello stesso processo clingo, quindi questo RSS include
     anche l'engine Prolog, il database asserito e i file runtime in /tmp. E' un
     confronto corretto purche' dichiarato cosi': "picco memoria del processo
     solver", non "memoria del solo grounding". Conseguenza pratica: l'overhead
     fisso dell'engine fa si' che a n piccolo il lazy possa consumare PIU' RSS
     dello standard; il risparmio e' asintotico ed emerge quando l'esplosione
     combinatoria delle euristiche ground dello standard supera quell'overhead.

8. ground_heuristics
   - Comando sorgente: benchmark_runner.py riesegue Clingo con `--text`.
   - Conteggio: numero di righe del programma ground testuale che iniziano con
     `#heuristic`.

9. ground_lazy_heuristic_facts
   - Comando sorgente: stesso run `clingo --text`.
   - Conteggio: numero di righe che iniziano con `__heuristic(`.

10. ground_facts
    - Comando sorgente: stesso run `clingo --text`.
    - Conteggio: righe che sono fatti ground, cioe' terminano con `.` e non
      contengono `:-`; i fatti `__heuristic(...)` sono inclusi.

11. ground_lines
    - Comando sorgente: stesso run `clingo --text`.
    - Conteggio diagnostico: numero totale di righe stampate nell'output
      testuale ground. Non viene usato come conteggio delle regole ground;
      per quello si usa sempre la colonna `rules` da Clingo stats.

12. ground_query_heuristic_facts
    - Comando sorgente: stesso run `clingo --text`.
    - Conteggio: fatti query-driven `heuristic(...)` usati dalle euristiche
      lazy Alpha/Clingo-like.

13. ground_text_wall_s
    - Comando sorgente: stesso run `clingo --text`.
    - Misura: tempo wall-clock del run testuale, inclusa produzione e cattura
      dell'output.

14. combined_heuristics
    - Non e' una colonna del CSV: viene calcolata qui come
      `ground_heuristics + ground_lazy_heuristic_facts +
      ground_query_heuristic_facts`.

15. solving_ms_per_choice
    - Non e' una colonna del CSV: viene calcolata qui come
      `1000 * solving_s / choices` quando il numero di scelte e' positivo.

16. total_prolog_query_time_ms (e le altre LAZY_PROLOG_METRIC_FIELDS)
    - Comando sorgente: stesso run JSON di Clingo; il propagatore lazy stampa su
      stderr la riga `[lazy-prolog] summary ...` quando LAZY_PROLOG_STATS=1.
    - Significato: tempo wall speso nell'engine SWI-Prolog in-process per
      rispondere alle query euristiche per-decisione. Definito solo per le
      varianti lazy; per gli encoding standard non c'e' nessuna query Prolog.

17. prolog_ms_per_decide
    - Non e' una colonna del CSV: calcolata qui come
      `total_prolog_query_time_ms / decide_calls` quando decide_calls > 0.
    - E' il costo per-decisione del lazy, cioe' il prezzo in tempo che si paga
      per il grounding sub-lineare: la meta' "tempo" del trade-off di memoria.

Le colonne diagnostiche `status`, `failure_reason`, `exit_code` e
`memory_limit_hit` sono usate dallo script di benchmark per fermare una variante
dopo un hit di memoria; questo script le ignora nei grafici.
"""

import argparse
import csv
import os
import shutil
import sys
import textwrap
from collections import defaultdict


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TEST_ROOT = os.path.dirname(SCRIPT_DIR)

# Layout per-backend dei risultati e dei grafici.
BACKENDS = ("native", "prolog")


def results_dir_for(backend: str) -> str:
    return os.path.join(TEST_ROOT, f"results-{backend}")


def graphs_dir_for(backend: str) -> str:
    return os.path.join(TEST_ROOT, f"graphs-{backend}")


GRAPHS_COMPARE_DIR = os.path.join(TEST_ROOT, "graphs-native-prolog")

# Nomi CSV per (problema, backend).
BSP_CSV_TMPL = "1_BSP_{backend}.csv"
PUP_CSV_TMPL = "2_PUP_{backend}.csv"
BSP_RANDOM_CSV_TMPL = "1_BSP_{backend}_random.csv"

# Sottocartelle per problema dentro ogni albero di grafici.
BSP_SUBDIR = "1_BSP"
PUP_SUBDIR = "2_PUP"

# Varianti lazy (usate dal confronto native-vs-prolog).
LAZY_VARIANTS = ("la", "lc", "la_aux", "la_co")

# Strumentazione per-decisione emessa dal propagatore lazy tramite la riga
# stderr "[lazy-prolog] summary ..." (presente solo per le varianti lazy).
# Quantifica il rovescio della medaglia del lazy grounding: il costo in tempo
# delle query Prolog pagato a ogni decisione del solver.
LAZY_PROLOG_METRIC_FIELDS = [
    "decide_calls",
    "total_decide_time_ms",
    "total_state_sync_time_ms",
    "total_prolog_query_time_ms",
    "total_candidate_scan_time_ms",
    "total_literal_lookup_time_ms",
    "total_candidate_selection_time_ms",
    "total_candidates_seen",
    "max_candidates_seen",
    "avg_candidates_per_decide",
]

METRIC_FIELDS = [
    "grounding_s",
    "solving_s",
    "total_s",
    "choices",
    "conflicts",
    "restarts",
    "rules",
    "variables",
    "memory_mb",
    "ground_text_wall_s",
    "ground_heuristics",
    "ground_lazy_heuristic_facts",
    "ground_query_heuristic_facts",
    "ground_facts",
    "ground_lines",
    *LAZY_PROLOG_METRIC_FIELDS,
]
INTEGER_METRICS = {
    "choices",
    "conflicts",
    "restarts",
    "rules",
    "variables",
    "ground_heuristics",
    "ground_lazy_heuristic_facts",
    "ground_query_heuristic_facts",
    "combined_heuristics",
    "ground_facts",
    "ground_lines",
    "decide_calls",
    "total_candidates_seen",
    "max_candidates_seen",
}
LOWER_IS_BETTER_METRICS = {
    "grounding_s",
    "solving_s",
    "total_s",
    "choices",
    "conflicts",
    "restarts",
    "rules",
    "variables",
    "memory_mb",
    "combined_heuristics",
    "ground_lines",
    "solving_ms_per_choice",
    "total_prolog_query_time_ms",
    "total_decide_time_ms",
    "prolog_ms_per_decide",
}

PLOT_CONFIGS = [
    {
        "metric": "total_s",
        "title": "Total Time",
        "ylabel": "Time (seconds)",
        "description": "End-to-end Clingo time from JSON field Time.Total.",
        "filename": "total_time.png",
    },
    {
        "metric": "grounding_s",
        "title": "Grounding Time",
        "ylabel": "Time (seconds)",
        "description": "Derived estimate from clingo JSON stats: Time.Total minus Time.Solve.",
        "filename": "grounding_time.png",
    },
    {
        "metric": "solving_s",
        "title": "Solving Time",
        "ylabel": "Time (seconds)",
        "description": "Net time spent in CDNL search\n(grounding excluded)",
        "filename": "solving_time.png",
    },
    {
        "metric": "choices",
        "title": "Choices",
        "ylabel": "Number of choices",
        "description": "If the lazy heuristic guides the search correctly,\nchoices should remain comparable",
        "filename": "choices_comparison.png",
    },
    {
        "metric": "conflicts",
        "title": "Conflicts",
        "ylabel": "Number of conflicts",
        "description": "Conflicts trigger backtracking.\nFewer conflicts = better heuristic guidance",
        "filename": "conflicts_comparison.png",
    },
    {
        "metric": "restarts",
        "title": "Restarts",
        "ylabel": "Number of restarts",
        "description": "Number of search restarts used by CDNL",
        "filename": "restarts_comparison.png",
    },
    {
        "metric": "solving_ms_per_choice",
        "title": "Solving Cost per Choice",
        "ylabel": "Milliseconds per decision",
        "description": "Derived as 1000 * solving_s / choices. Lower values mean that each solver decision is cheaper.",
        "filename": "solving_cost_per_choice.png",
    },
    {
        "metric": "rules",
        "title": "Solver Rules",
        "ylabel": "Rules (millions)",
        "description": "Ground rules reported by the same clingo run used for timing, from JSON stats field Stats.LP.Rules.Final.",
        "filename": "solver_rules.png",
    },
    {
        "metric": "ground_lines",
        "title": "Ground Text Lines",
        "ylabel": "Lines in --text output (millions)",
        "description": "Diagnostic line count of clingo --text output; solver rule counts are taken from clingo stats.",
        "filename": "ground_program_lines.png",
    },
    {
        "metric": "memory_mb",
        "title": "RSS Memory",
        "ylabel": "Memory (GB)",
        "description": "Peak RSS of the whole solver process (grounding + search + propagator).\nFor lazy variants it also includes the in-process SWI-Prolog engine, its\nasserted DB and /tmp runtime files; not grounding-only memory.",
        "filename": "memory_comparison.png",
    },
    {
        "metric": "ground_heuristics",
        "title": "Ground Native Heuristics",
        "ylabel": "#heuristic directives",
        "description": "Rows starting with #heuristic in clingo --text output.",
        "filename": "ground_heuristics.png",
    },
    {
        "metric": "ground_lazy_heuristic_facts",
        "title": "Ground Lazy Heuristic Facts",
        "ylabel": "__heuristic facts",
        "description": "Rows starting with __heuristic( in clingo --text output.",
        "filename": "ground_lazy_heuristic_facts.png",
    },
    {
        "metric": "combined_heuristics",
        "title": "Heuristic Grounding",
        "ylabel": "Ground heuristic entries (millions)",
        "description": "Standard: native #heuristic directives\nLazy: __heuristic and query-driven heuristic facts passed to the propagator",
        "filename": "combined_heuristics.png",
    },
    {
        "metric": "prolog_ms_per_decide",
        "title": "Prolog Query Cost per Decision",
        "ylabel": "Milliseconds per decision",
        "description": "Derived as total_prolog_query_time_ms / decide_calls. The price the\nlazy approach pays for sub-linear grounding: defined only for lazy\nvariants, since standard encodings issue no per-decision Prolog query.",
        "filename": "prolog_ms_per_decide.png",
    },
    {
        "metric": "total_prolog_query_time_ms",
        "title": "Total Prolog Query Time",
        "ylabel": "Time (ms)",
        "description": "Wall time spent inside the in-process SWI-Prolog engine answering\nper-decision heuristic queries. Lazy variants only; the standard\nground-and-solve encodings never call Prolog during search.",
        "filename": "total_prolog_query_time.png",
    },
]

PLOT_CONFIG_BY_METRIC = {
    config["metric"]: config
    for config in PLOT_CONFIGS
}

MAIN_PLOT_LAYOUT = [
    PLOT_CONFIG_BY_METRIC["grounding_s"],
    PLOT_CONFIG_BY_METRIC["solving_s"],
    PLOT_CONFIG_BY_METRIC["total_s"],
    PLOT_CONFIG_BY_METRIC["memory_mb"],
    PLOT_CONFIG_BY_METRIC["choices"],
    PLOT_CONFIG_BY_METRIC["conflicts"],
    PLOT_CONFIG_BY_METRIC["restarts"],
    PLOT_CONFIG_BY_METRIC["solving_ms_per_choice"],
    PLOT_CONFIG_BY_METRIC["prolog_ms_per_decide"],
    PLOT_CONFIG_BY_METRIC["total_prolog_query_time_ms"],
    PLOT_CONFIG_BY_METRIC["rules"],
    PLOT_CONFIG_BY_METRIC["combined_heuristics"],
]

INTERPRETIVE_PLOT_CONFIGS = [
    {
        "kind": "grounding_time_vs_heuristic_size",
        "title": "Grounding Time vs Heuristic Objects",
        "ylabel": "Grounding time (seconds)",
        "xlabel": "Ground heuristic objects",
        "description": "Scatter plot relating grounding time to the number of materialized heuristic objects.",
        "filename": "grounding_time_vs_heuristic_size.png",
    },
    {
        "kind": "lazy_standard_solving_time_ratio",
        "title": "Lazy / Standard Solving-Time Ratio",
        "ylabel": "Lazy / standard solving time (x)",
        "description": "Solving-time ratio for each lazy encoding against its paired standard encoding. Values above 1 indicate that the lazy run took longer in solving.",
        "filename": "lazy_standard_solving_time_ratio.png",
    },
]

MAIN_PLOT_LAYOUT.extend(INTERPRETIVE_PLOT_CONFIGS)


BSP_THEME = {
    "variant_labels": {
        "gc_noheur": "G&S + Clingo sem (no heur)",
        "gc": "G&S + Clingo sem",
        "ga": "G&S + Alpha sem",
        "ga_weak": "G&S + Alpha sem (weak)",
        "la": "Lazy + Alpha sem",
        "lc": "Lazy + Clingo sem",
        "la_aux": "Lazy + Alpha sem + Aux",
        "la_co": "Lazy + Alpha sem + Constr Opt",
    },
    "variant_files": {
        "gc_noheur": "encodings-native/1_BSP/BSP_gc_noheur.lp",
        "gc": "encodings-native/1_BSP/BSP_gc.lp",
        "ga": "encodings-native/1_BSP/BSP_ga.lp",
        "ga_weak": "encodings-native/1_BSP/BSP_ga_weak.lp",
        "la": "encodings-native/1_BSP/BSP_la.lp",
        "lc": "encodings-native/1_BSP/BSP_lc.lp",
        "la_aux": "encodings-native/1_BSP/BSP_la_aux.lp",
        "la_co": "encodings-native/1_BSP/BSP_la_co.lp",
    },
    "variant_colors": {
        "gc_noheur": "#34495E",
        "gc":  "#E74C3C",
        "ga": "#F39C12",
        "ga_weak": "#D68910",
        "la":   "#2ECC71",
        "lc": "#9B59B6",
        "la_aux": "#16A085",
        "la_co": "#3498DB",
    },
    "variant_markers": {
        "gc_noheur": "X",
        "gc":  "o",
        "ga": "^",
        "ga_weak": "v",
        "la":   "o",
        "lc": "s",
        "la_aux": "^",
        "la_co": "D",
    },
    "variant_linestyles": {
        "gc_noheur": ":",
        "gc": "--",
        "ga": "--",
        "ga_weak": "--",
        "la": "-",
        "lc": "-",
        "la_aux": "-",
        "la_co": "-.",
    },
    "variant_order": ["gc_noheur", "gc", "ga", "ga_weak", "la", "lc", "la_aux", "la_co"],
    "include_zero_metric_variants": {
        "combined_heuristics": ["gc_noheur"],
    },
    "xlabel": "Problem size (N)",
    "suptitle": "BSP Benchmark: Standard vs Lazy Heuristic Grounding",
    "baseline": "gc_noheur",
    "heuristic_baseline": "gc",
    "comparison_pairs": [
        ("gc", "lc", "gc / lc"),
        ("ga", "la", "ga / la"),
    ],
    "lazy_standard_solving_time_ratio_pairs": [
        ("gc", "lc"),
        ("ga", "la"),
    ],
}


# PUP usa lo STESSO schema di varianti di BSP (gc_noheur, gc, ga, la, lc):
# standard ground-and-solve (gc/ga) contro lazy (la/lc), piu' il baseline
# senza euristica (gc_noheur). Non esistono piu' le famiglie pup_double*.
PUP_THEME = {
    "variant_labels": {
        "gc_noheur": "G&S + Clingo sem (no heur)",
        "gc": "G&S + Clingo sem",
        "ga": "G&S + Alpha sem",
        "la": "Lazy + Alpha sem",
        "lc": "Lazy + Clingo sem",
    },
    "variant_files": {
        "gc_noheur": "encodings-native/2_PUP/PUP_gc_noheur.lp",
        "gc": "encodings-native/2_PUP/PUP_gc.lp",
        "ga": "encodings-native/2_PUP/PUP_ga.lp",
        "la": "encodings-native/2_PUP/PUP_la.lp",
        "lc": "encodings-native/2_PUP/PUP_lc.lp",
    },
    "variant_colors": {
        "gc_noheur": "#34495E",
        "gc": "#E74C3C",
        "ga": "#F39C12",
        "la": "#2ECC71",
        "lc": "#9B59B6",
    },
    "variant_markers": {
        "gc_noheur": "X",
        "gc": "o",
        "ga": "^",
        "la": "o",
        "lc": "s",
    },
    "variant_linestyles": {
        "gc_noheur": ":",
        "gc": "--",
        "ga": "--",
        "la": "-",
        "lc": "-",
    },
    "variant_order": ["gc_noheur", "gc", "ga", "la", "lc"],
    "include_zero_metric_variants": {
        "combined_heuristics": ["gc_noheur"],
    },
    "xlabel": "Instance size (N)",
    "suptitle": "PUP Benchmark: Standard vs Lazy Heuristic Grounding",
    "baseline": "gc_noheur",
    "heuristic_baseline": "gc",
    "comparison_pairs": [
        ("gc", "lc", "gc / lc"),
        ("ga", "la", "ga / la"),
    ],
    "lazy_standard_solving_time_ratio_pairs": [
        ("gc", "lc"),
        ("ga", "la"),
    ],
}


def load_csv(csv_path: str):


    raw = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            variant = row["variant"].strip()
            n = int(row["n"])
            row_values = {}
            raw[variant][n]["attempted_runs"].append(1.0)

            for metric in METRIC_FIELDS:
                val_str = row.get(metric, "").strip()
                if val_str not in ("NA", ""):
                    try:
                        value = float(val_str)
                        row_values[metric] = value
                    except ValueError:
                        pass

            solving = row_values.get("solving_s")
            choices = row_values.get("choices")
            if solving is not None and choices is not None and choices > 0:
                row_values["solving_ms_per_choice"] = 1000.0 * solving / choices

            # total_prolog_query_time_ms is already in milliseconds and
            # decide_calls is a pure count, so the ratio is ms per decision.
            prolog_query_ms = row_values.get("total_prolog_query_time_ms")
            decide_calls = row_values.get("decide_calls")
            if prolog_query_ms is not None and decide_calls is not None and decide_calls > 0:
                row_values["prolog_ms_per_decide"] = prolog_query_ms / decide_calls

            legacy_failed_run = _looks_like_legacy_failed_lazy_run(row_values)

            solver_status = row.get("solver_status", row.get("status", "")).strip()
            ground_status = row.get("ground_status", "").strip()
            if not ground_status:
                general_status = row.get("status", "").strip()
                if general_status == "ok":
                    ground_status = "ok"
                elif general_status == "timeout" and "ground_lines" in row_values:
                    ground_status = "ok"
                else:
                    ground_status = general_status

            solver_metrics = {
                "grounding_s",
                "solving_s",
                "total_s",
                "choices",
                "conflicts",
                "restarts",
                "solving_ms_per_choice",
                "rules",
                "variables",
                "memory_mb",
                # Per-decision propagator stats come from the same JSON solver
                # run (its stderr), so they share its validity.
                *LAZY_PROLOG_METRIC_FIELDS,
                "prolog_ms_per_decide",
            }
            
            ground_metrics = {
                "ground_heuristics",
                "ground_lazy_heuristic_facts",
                "ground_query_heuristic_facts",
                "ground_facts",
                "ground_lines",
            }

            invalid_metrics = set()
            if legacy_failed_run:
                invalid_metrics.update(solver_metrics)
            
            if solver_status and solver_status != "ok":
                invalid_metrics.update(solver_metrics)
                
            if ground_status and ground_status != "ok":
                invalid_metrics.update(ground_metrics)

            for metric, value in row_values.items():
                if metric in invalid_metrics:
                    continue
                raw[variant][n][metric].append(value)

            heuristic_values = [
                row_values[m]
                for m in (
                    "ground_heuristics",
                    "ground_lazy_heuristic_facts",
                    "ground_query_heuristic_facts",
                )
                if m in row_values
            ]
            if heuristic_values:
                raw[variant][n]["combined_heuristics"].append(sum(heuristic_values))

            if not legacy_failed_run and "grounding_s" not in row_values:
                total = row_values.get("total_s")
                solving = row_values.get("solving_s")
                if total is not None and solving is not None:
                    raw[variant][n]["grounding_s"].append(max(total - solving, 0.0))

    return raw


def _looks_like_legacy_failed_lazy_run(row_values: dict) -> bool:


    return (
        row_values.get("ground_lazy_heuristic_facts", 0.0) > 0.0 and
        row_values.get("rules") == 0.0 and
        row_values.get("choices") == 0.0 and
        row_values.get("conflicts") == 0.0 and
        row_values.get("solving_s") == 0.0 and
        row_values.get("variables", 0.0) > 0.0
    )


def compute_stats(raw):


    import statistics

    result = {}
    for variant, n_data in raw.items():
        result[variant] = defaultdict(lambda: {"n": [], "mean": [], "gc": [], "count": []})
        for n in sorted(n_data.keys()):
            for metric, values in n_data[n].items():
                if len(values) > 0:
                    mean_val = statistics.mean(values)
                    std_val = statistics.pstdev(values) if len(values) > 1 else 0.0
                    result[variant][metric]["n"].append(n)
                    result[variant][metric]["mean"].append(mean_val)
                    result[variant][metric]["gc"].append(std_val)
                    result[variant][metric]["count"].append(len(values))

    return result


def _load_random_variability_rows(csv_path: str, theme: dict):

    data = defaultdict(
        lambda: defaultdict(
            lambda: defaultdict(
                lambda: defaultdict(lambda: defaultdict(list))
            )
        )
    )
    supported_variants = set(theme.get("variant_order", []))

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            variant = row.get("variant", "").strip()
            if variant not in supported_variants:
                continue

            solver_status = row.get("solver_status", row.get("status", "")).strip()
            if solver_status and solver_status != "ok":
                continue

            try:
                n = int(row["n"])
                seed = int(row.get("seed", "0"))
            except (KeyError, TypeError, ValueError):
                continue

            setting = row.get("setting", "").strip() or "seed_only"
            for metric, _title, _ylabel in RANDOM_VARIABILITY_METRICS:
                value_text = row.get(metric, "").strip()
                if value_text in ("", "NA"):
                    continue
                try:
                    value = float(value_text)
                except ValueError:
                    continue
                data[setting][metric][variant][seed][n].append(value)

    return data


def _has_random_variability_data(setting_data: dict) -> bool:

    for metric_data in setting_data.values():
        for variant_data in metric_data.values():
            if len(variant_data) > 1:
                return True
    return False


def _setting_display_name(setting: str) -> str:

    return setting.replace("_", " ")


def generate_random_variability_graphs(csv_path: str, graphs_dir: str, theme: dict) -> None:

    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return

    random_data = _load_random_variability_rows(csv_path, theme)
    if not random_data:
        return

    for setting in sorted(random_data):
        setting_data = random_data[setting]
        if not _has_random_variability_data(setting_data):
            continue

        fig, axes = plt.subplots(2, 2, figsize=(13, 8.4))
        axes_flat = axes.flatten()
        plotted_any = False

        for ax, (metric, title, ylabel) in zip(axes_flat, RANDOM_VARIABILITY_METRICS):
            metric_data = setting_data.get(metric, {})
            has_data = False
            for variant in _ordered_variants(metric_data, theme):
                variant_data = metric_data.get(variant, {})
                if not variant_data:
                    continue

                color = theme["variant_colors"].get(variant)
                marker = theme["variant_markers"].get(variant, "o")
                linestyle = _variant_linestyle(variant, theme)
                per_n = defaultdict(list)

                for seed, n_values in sorted(variant_data.items()):
                    xs = sorted(n_values)
                    ys = [
                        sum(n_values[n]) / len(n_values[n])
                        for n in xs
                    ]
                    if not xs:
                        continue
                    has_data = True
                    plotted_any = True
                    for n, value in zip(xs, ys):
                        per_n[n].append(value)
                    ax.plot(
                        xs,
                        ys,
                        color=color,
                        linewidth=0.9,
                        alpha=0.28,
                        marker=marker,
                        markersize=3,
                        markeredgewidth=0,
                        label="_nolegend_",
                    )

                if per_n:
                    xs = sorted(per_n)
                    ys = [sum(per_n[n]) / len(per_n[n]) for n in xs]
                    ax.plot(
                        xs,
                        ys,
                        color=color,
                        linestyle=linestyle,
                        linewidth=2.2,
                        marker=marker,
                        markersize=5,
                        markeredgecolor="white",
                        markeredgewidth=0.7,
                        label=theme["variant_labels"].get(variant, variant),
                    )

            ax.set_title(title, fontsize=12, fontweight="bold")
            ax.set_xlabel(theme.get("xlabel", "Problem size (N)"))
            ax.set_ylabel(ylabel)
            ax.grid(True, alpha=0.3, linestyle="--")
            _apply_y_axis_format(ax, metric)
            if has_data:
                ax.legend(fontsize=8)
            else:
                ax.text(
                    0.5,
                    0.5,
                    "No data",
                    transform=ax.transAxes,
                    ha="center",
                    va="center",
                    fontsize=12,
                    color="#AAA",
                )

        if not plotted_any:
            plt.close(fig)
            continue

        fig.suptitle(
            "BSP Randomized Search Variability\n"
            f"setting: {_setting_display_name(setting)}; thin lines are individual seeds, thick lines are seed means",
            fontsize=14,
            fontweight="bold",
        )
        plt.tight_layout(rect=[0, 0.02, 1, 0.94], h_pad=2.8, w_pad=2.5)
        filename = f"random_variability{_filename_suffix(setting)}.png"
        out_path = os.path.join(graphs_dir, filename)
        plt.savefig(out_path, dpi=200, bbox_inches="tight")
        plt.close(fig)
        print(f"  Random variability chart saved to '{out_path}'.")


VARIANT_FILL_ALPHA = 0.15
CAPTION_COLOR = "#5F6368"
SEPARATOR_COLOR = "#D6D6D6"
VERTICAL_SEPARATOR_GAP_FRACTION = 0.42
OVERLAP_OFFSET_POINTS = 4.5
OVERLAP_CAPTION = (
    "For readability, small vertical offsets are applied to overlapping curves "
    "in count-based plots only; the offsets do not represent differences in "
    "the measured values."
)
OFFSET_METRICS = {
    "variables",
}
ENDPOINT_LABEL_METRICS = {
    config["metric"]
    for config in PLOT_CONFIGS
}
ENDPOINT_LABEL_MIN_GAP_POINTS = 9.0
ENDPOINT_LABEL_AXIS_PAD_POINTS = 4.0
ENDPOINT_LABEL_X_GAP_POINTS = 18.0
SHARED_Y_SCALE_METRIC_GROUPS = (
    ("ground_heuristics", "ground_lazy_heuristic_facts"),
)
VARIANT_LINESTYLES = [
    "-",
    "--",
    "-.",
    ":",
    (0, (5, 2)),
    (0, (3, 1, 1, 1)),
    (0, (1, 1)),
]
THOUSAND_FORMAT_METRICS = {
    "restarts",
}
MILLION_SUFFIX_FORMAT_METRICS = {
    "choices",
    "conflicts",
}
MILLION_FORMAT_METRICS = {
    "ground_lines",
    "rules",
    "variables",
    "combined_heuristics",
}

RANDOM_VARIABILITY_METRICS = [
    ("total_s", "Total Time", "Time (seconds)"),
    ("solving_s", "Solving Time", "Time (seconds)"),
    ("choices", "Choices", "Number of choices"),
    ("conflicts", "Conflicts", "Number of conflicts"),
]


def _add_axis_caption(ax, description: str, *, y: float, width: int, fontsize: int):

    lines = []
    for line in description.splitlines():
        line = " ".join(line.split())
        if line:
            lines.append(textwrap.fill(line, width=width))
    wrapped = "\n".join(lines)
    ax.text(
        0.5, y, wrapped,
        transform=ax.transAxes,
        fontsize=fontsize,
        color=CAPTION_COLOR,
        ha="center",
        va="top",
        fontstyle="italic",
        clip_on=False,
    )


def _finite_xy(x_values, y_values):

    import math

    points = []
    for x, y in zip(x_values, y_values):
        if math.isfinite(float(x)) and math.isfinite(float(y)):
            points.append((float(x), float(y)))
    return points


def _series_signature(x_values, y_values):

    return tuple((round(x, 10), round(y, 10)) for x, y in _finite_xy(x_values, y_values))


def _display_offsets_for_series(series, *, enabled: bool = True):

    if not enabled:
        return {item["key"]: 0.0 for item in series}

    grouped = defaultdict(list)
    for item in series:
        signature = _series_signature(item["x"], item["y"])
        if signature:
            grouped[signature].append(item["key"])

    offsets = {item["key"]: 0.0 for item in series}
    for keys in grouped.values():
        if len(keys) <= 1:
            continue
        center = (len(keys) - 1) / 2.0
        for idx, key in enumerate(keys):
            offsets[key] = (idx - center) * OVERLAP_OFFSET_POINTS
    return offsets


def _display_offsets_for_metric(metric: str, series):

    return _display_offsets_for_series(series, enabled=metric in OFFSET_METRICS)


def _overlapped_series_keys(series) -> set:

    grouped = defaultdict(list)
    for item in series:
        signature = _series_signature(item["x"], item["y"])
        if signature:
            grouped[signature].append(item["key"])

    overlapped = set()
    for keys in grouped.values():
        if len(keys) > 1:
            overlapped.update(keys)
    return overlapped


def _offset_data_transform(ax, y_points: float):

    if not y_points:
        return ax.transData

    import matplotlib.transforms as transforms

    return ax.transData + transforms.ScaledTranslation(
        0,
        y_points / 72.0,
        ax.figure.dpi_scale_trans,
    )


def _has_visual_offsets(offsets: dict) -> bool:

    return any(abs(offset) > 0 for offset in offsets.values())


def _caption_with_overlap_note(description: str, offsets: dict) -> str:

    if not _has_visual_offsets(offsets):
        return description
    return f"{description}\n{OVERLAP_CAPTION}"


def _variant_linestyle(variant: str, theme: dict):

    styles = theme.get("variant_linestyles", {})
    if variant in styles:
        return styles[variant]

    ordered = theme.get("variant_order", [])
    if variant in ordered:
        return VARIANT_LINESTYLES[ordered.index(variant) % len(VARIANT_LINESTYLES)]
    return "-"


def _endpoint_label(theme: dict, variant: str) -> str:

    return _variant_dir_identifier(theme, variant)


def _has_positive_metric(stats: dict, variant: str, metric: str) -> bool:

    data = stats.get(variant, {}).get(metric)
    if not data:
        return False
    return any(value > 0 for value in data.get("mean", []))


def _include_variant_for_metric(stats: dict, variant: str, metric: str, theme: dict | None = None) -> bool:

    if metric == "ground_heuristics":
        return _has_positive_metric(stats, variant, "ground_heuristics")
    if metric == "ground_lazy_heuristic_facts":
        return _has_positive_metric(stats, variant, "ground_lazy_heuristic_facts")
    if metric == "combined_heuristics":
        if (
            _has_positive_metric(stats, variant, "ground_heuristics") or
            _has_positive_metric(stats, variant, "ground_lazy_heuristic_facts") or
            _has_positive_metric(stats, variant, "ground_query_heuristic_facts")
        ):
            return True
        zero_metric_variants = (theme or {}).get("include_zero_metric_variants", {})
        return variant in set(zero_metric_variants.get(metric, []))
    return True


def _shared_y_scale_limits(stats: dict, theme: dict, metrics) -> tuple | None:

    import math

    min_value = 0.0
    max_value = 0.0
    has_value = False

    for metric in metrics:
        for variant in _ordered_variants(stats, theme):
            if not _include_variant_for_metric(stats, variant, metric, theme):
                continue
            data = stats.get(variant, {}).get(metric)
            if not data:
                continue

            means = data.get("mean", [])
            deviations = data.get("gc", [0.0] * len(means))
            for mean, deviation in zip(means, deviations):
                if not math.isfinite(float(mean)):
                    continue
                deviation = deviation if math.isfinite(float(deviation)) else 0.0
                min_value = min(min_value, float(mean) - float(deviation))
                max_value = max(max_value, float(mean) + float(deviation))
                has_value = True

    if not has_value:
        return None

    span = max_value - min_value
    pad = max(span * 0.05, max_value * 0.02, 1.0)
    return min(0.0, min_value - pad), max_value + pad


def _shared_y_scale_limits_by_metric(stats: dict, theme: dict) -> dict:

    limits = {}
    for metrics in SHARED_Y_SCALE_METRIC_GROUPS:
        metric_limits = _shared_y_scale_limits(stats, theme, metrics)
        if metric_limits is None:
            continue
        for metric in metrics:
            limits[metric] = metric_limits
    return limits


def _endpoint_label_offsets(ax, series, visual_offsets=None) -> dict:

    visual_offsets = visual_offsets or {}

    endpoints = []
    for item in series:
        points = _finite_xy(item["x"], item["y"])
        if not points:
            continue
        x, y = points[-1]
        x_px, y_px = ax.transData.transform((x, y))
        y_px += visual_offsets.get(item["key"], 0.0) * ax.figure.dpi / 72.0
        endpoints.append((x_px, y_px, item["key"]))

    offsets = {item["key"]: 0.0 for item in series}
    if not endpoints:
        return offsets

    point_to_px = ax.figure.dpi / 72.0
    min_gap_px = ENDPOINT_LABEL_MIN_GAP_POINTS * point_to_px
    x_gap_px = ENDPOINT_LABEL_X_GAP_POINTS * point_to_px

    groups = []
    pending = set(range(len(endpoints)))
    while pending:
        seed = pending.pop()
        group_indices = [seed]
        stack = [seed]
        while stack:
            left = stack.pop()
            left_x, left_y, _ = endpoints[left]
            connected = [
                right
                for right in pending
                if (
                    abs(endpoints[right][1] - left_y) <= min_gap_px and
                    abs(endpoints[right][0] - left_x) <= x_gap_px
                )
            ]
            for right in connected:
                pending.remove(right)
                stack.append(right)
                group_indices.append(right)
        groups.append(sorted((endpoints[index] for index in group_indices), key=lambda item: item[1]))

    ylim = ax.get_ylim()
    y0_px = ax.transData.transform((0.0, ylim[0]))[1]
    y1_px = ax.transData.transform((0.0, ylim[1]))[1]
    axis_min_px, axis_max_px = sorted((y0_px, y1_px))
    axis_pad_px = ENDPOINT_LABEL_AXIS_PAD_POINTS * point_to_px

    for group in groups:
        if len(group) <= 1:
            continue
        center = (len(group) - 1) / 2.0
        group_offsets = []
        for idx, (_, _, key) in enumerate(group):
            group_offsets.append((key, (idx - center) * ENDPOINT_LABEL_MIN_GAP_POINTS))

        bottom_px = min(
            y_px + offset * point_to_px
            for (_, y_px, _), (_, offset) in zip(group, group_offsets)
        )
        top_px = max(
            y_px + offset * point_to_px
            for (_, y_px, _), (_, offset) in zip(group, group_offsets)
        )
        shift_px = 0.0
        if bottom_px < axis_min_px + axis_pad_px:
            shift_px += axis_min_px + axis_pad_px - bottom_px
        if top_px + shift_px > axis_max_px - axis_pad_px:
            shift_px += axis_max_px - axis_pad_px - (top_px + shift_px)

        shift_points = shift_px / point_to_px
        for key, offset in group_offsets:
            offsets[key] = offset + shift_points

    return offsets


def _annotate_series_endpoints(ax, series, *, label_fn, visual_offsets=None):

    visual_offsets = visual_offsets or {}

    if not series:
        return

    try:
        import matplotlib.patheffects as path_effects
    except ImportError:
        path_effects = None

    offsets = _endpoint_label_offsets(ax, series, visual_offsets)

    for item in series:
        points = _finite_xy(item["x"], item["y"])
        if not points:
            continue

        x, y = points[-1]
        visual_offset = visual_offsets.get(item["key"], 0.0)
        text = ax.annotate(
            label_fn(item),
            xy=(x, y),
            xytext=(7, visual_offset + offsets.get(item["key"], 0.0)),
            textcoords="offset points",
            color=item.get("color"),
            fontsize=item.get("fontsize", 7),
            fontweight="bold",
            va="center",
            ha="left",
            clip_on=False,
            zorder=8,
        )
        if path_effects is not None:
            text.set_path_effects([
                path_effects.Stroke(linewidth=2.5, foreground="white"),
                path_effects.Normal(),
            ])


def _annotate_metric_endpoints(ax, series, theme, metric: str, visual_offsets=None):

    if metric not in ENDPOINT_LABEL_METRICS:
        return

    _annotate_series_endpoints(
        ax,
        series,
        label_fn=lambda item: _endpoint_label(theme, item["variant"]),
        visual_offsets=visual_offsets,
    )


def _expand_flat_integer_axis(ax, series, metric: str):

    if metric not in INTEGER_METRICS:
        return

    values = [
        y
        for item in series
        for _, y in _finite_xy(item["x"], item["y"])
    ]
    if not values:
        return

    min_value = min(values)
    max_value = max(values)
    if min_value != max_value:
        return

    if min_value >= 0:
        upper = max(max_value + 1.0, max_value * 1.2, 1.0)
        ax.set_ylim(0.0, upper)
    else:
        pad = max(abs(min_value) * 0.1, 1.0)
        ax.set_ylim(min_value - pad, max_value + pad)


def _annotate_overlap_endpoints(ax, series, offsets, *, label_fn):

    if not _has_visual_offsets(offsets):
        return

    overlapped_keys = _overlapped_series_keys(series)

    try:
        import matplotlib.patheffects as path_effects
    except ImportError:
        path_effects = None

    for item in series:
        if item["key"] not in overlapped_keys:
            continue
        offset = offsets.get(item["key"], 0.0)
        points = _finite_xy(item["x"], item["y"])
        if not points:
            continue

        x, y = points[-1]
        text = ax.annotate(
            label_fn(item),
            xy=(x, y),
            xytext=(7, offset),
            textcoords="offset points",
            color=item.get("color"),
            fontsize=item.get("fontsize", 7),
            fontweight="bold",
            va="center",
            ha="left",
            clip_on=False,
            zorder=8,
        )
        if path_effects is not None:
            text.set_path_effects([
                path_effects.Stroke(linewidth=2.5, foreground="white"),
                path_effects.Normal(),
            ])


def _format_compact_number(value, _pos=None):

    abs_value = abs(value)
    for suffix, scale in (("B", 1_000_000_000), ("M", 1_000_000), ("K", 1_000)):
        if abs_value >= scale:
            scaled = value / scale
            if abs(scaled) >= 100 or scaled.is_integer():
                return f"{scaled:.0f}{suffix}"
            if abs(scaled) >= 10:
                return f"{scaled:.1f}{suffix}"
            return f"{scaled:.2f}".rstrip("0").rstrip(".") + suffix
    if abs_value >= 1:
        return f"{value:.0f}"
    if value == 0:
        return "0"
    return f"{value:g}"


def _format_millions(value, _pos=None):

    scaled = value / 1_000_000
    abs_scaled = abs(scaled)
    if value == 0:
        return "0"
    if abs_scaled >= 100 or scaled.is_integer():
        return f"{scaled:.0f}"
    if abs_scaled >= 10:
        return f"{scaled:.1f}".rstrip("0").rstrip(".")
    if abs_scaled >= 1:
        return f"{scaled:.2f}".rstrip("0").rstrip(".")
    return f"{scaled:.3f}".rstrip("0").rstrip(".")


def _format_fixed_thousands(value, _pos=None):

    scaled = value / 1_000
    abs_scaled = abs(scaled)
    if value == 0:
        return "0"
    if abs_scaled >= 100 or scaled.is_integer():
        return f"{scaled:.0f}K"
    if abs_scaled >= 10:
        return f"{scaled:.1f}".rstrip("0").rstrip(".") + "K"
    if abs_scaled >= 1:
        return f"{scaled:.2f}".rstrip("0").rstrip(".") + "K"
    return f"{scaled:.3f}".rstrip("0").rstrip(".") + "K"


def _format_fixed_millions(value, _pos=None):

    scaled = value / 1_000_000
    abs_scaled = abs(scaled)
    if value == 0:
        return "0"
    if abs_scaled >= 100 or scaled.is_integer():
        return f"{scaled:.0f}M"
    if abs_scaled >= 10:
        return f"{scaled:.1f}".rstrip("0").rstrip(".") + "M"
    if abs_scaled >= 1:
        return f"{scaled:.2f}".rstrip("0").rstrip(".") + "M"
    return f"{scaled:.3f}".rstrip("0").rstrip(".") + "M"


def _format_thousands(value, _pos=None):

    abs_value = abs(value)
    if abs_value >= 1_000:
        scaled = value / 1_000
        if abs(scaled) >= 100 or scaled.is_integer():
            return f"{scaled:.0f}K"
        if abs(scaled) >= 10:
            return f"{scaled:.1f}".rstrip("0").rstrip(".") + "K"
        return f"{scaled:.2f}".rstrip("0").rstrip(".") + "K"
    if abs_value >= 1:
        return f"{value:.0f}"
    if value == 0:
        return "0"
    return f"{value:g}"


def _format_memory_gb_from_mb(value, _pos=None):

    gb_value = value / 1024
    abs_value = abs(gb_value)
    if abs_value >= 100 or gb_value.is_integer():
        return f"{gb_value:.0f}"
    if abs_value >= 10:
        return f"{gb_value:.1f}".rstrip("0").rstrip(".")
    if abs_value >= 0.01:
        return f"{gb_value:.2f}".rstrip("0").rstrip(".")
    if value == 0:
        return "0"
    return f"{gb_value:.3g}"


def _apply_y_axis_format(ax, metric: str):

    from matplotlib.ticker import FuncFormatter, MaxNLocator

    if metric == "memory_mb":
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6))
        ax.yaxis.set_major_formatter(FuncFormatter(_format_memory_gb_from_mb))
    elif metric in THOUSAND_FORMAT_METRICS:
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6, integer=True))
        ax.yaxis.set_major_formatter(FuncFormatter(_format_fixed_thousands))
    elif metric in MILLION_SUFFIX_FORMAT_METRICS:
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6, integer=True))
        ax.yaxis.set_major_formatter(FuncFormatter(_format_fixed_millions))
    elif metric in MILLION_FORMAT_METRICS:
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6, integer=True, prune="upper"))
        ax.yaxis.set_major_formatter(FuncFormatter(_format_millions))
    elif metric in INTEGER_METRICS:
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6, integer=True))
        ax.yaxis.set_major_formatter(FuncFormatter(_format_compact_number))
    else:
        return

    ax.yaxis.offsetText.set_visible(False)


def _add_subplot_separators(fig, axes, n_plots: int):

    from matplotlib.lines import Line2D

    active_axes = axes.flatten()[:n_plots]
    if not active_axes.size:
        return

    fig.canvas.draw()
    positions = [ax.get_position() for ax in active_axes]
    y0 = min(pos.y0 for pos in positions)
    y1 = max(pos.y1 for pos in positions)
    x0 = min(pos.x0 for pos in positions)
    x1 = max(pos.x1 for pos in positions)

    n_rows, n_cols = axes.shape

    for col in range(1, n_cols):
        left_positions = [
            axes[row, col - 1].get_position()
            for row in range(n_rows)
            if row * n_cols + (col - 1) < n_plots
        ]
        right_positions = [
            axes[row, col].get_position()
            for row in range(n_rows)
            if row * n_cols + col < n_plots
        ]
        if not left_positions or not right_positions:
            continue

        left_edge = max(pos.x1 for pos in left_positions)
        right_edge = min(pos.x0 for pos in right_positions)
        x = left_edge + (right_edge - left_edge) * VERTICAL_SEPARATOR_GAP_FRACTION
        fig.add_artist(Line2D([x, x], [y0, y1], transform=fig.transFigure,
                              color=SEPARATOR_COLOR, linewidth=0.8))

    for row in range(1, n_rows):
        upper_positions = [
            axes[row - 1, col].get_position()
            for col in range(n_cols)
            if (row - 1) * n_cols + col < n_plots
        ]
        lower_positions = [
            axes[row, col].get_position()
            for col in range(n_cols)
            if row * n_cols + col < n_plots
        ]
        if not upper_positions or not lower_positions:
            continue

        y = (
            min(pos.y0 for pos in upper_positions) +
            max(pos.y1 for pos in lower_positions)
        ) / 2.0
        fig.add_artist(Line2D([x0, x1], [y, y], transform=fig.transFigure,
                              color=SEPARATOR_COLOR, linewidth=0.8))


def _format_title(metric: str, title: str) -> str:

    if metric in LOWER_IS_BETTER_METRICS:
        return f"{title}\n(Lower is better)"
    return title


def _ordered_variants(stats: dict, theme: dict):

    order = theme["variant_order"]
    present = set(stats.keys())
    ordered = [v for v in order if v in present]
    ordered.extend(sorted(present - set(ordered)))
    return ordered


def _filename_suffix(title_suffix: str) -> str:

    import re

    if not title_suffix:
        return ""
    normalized = title_suffix.lower().replace("+", " ")
    normalized = re.sub(r"[^a-z0-9]+", "_", normalized).strip("_")
    return f"_{normalized}" if normalized else ""


def _split_exclude_selectors(values) -> list:

    selectors = []
    for value in values or []:
        if isinstance(value, (list, tuple)):
            selectors.extend(_split_exclude_selectors(value))
            continue
        for item in value.split(","):
            item = item.strip()
            if item:
                selectors.append(item)
    return selectors


def _compact_filename_stem(filename: str) -> str:

    basename = os.path.basename(filename.replace("\\", "/"))
    stem, _ = os.path.splitext(basename)
    return stem.lower().replace("_", "").replace(" ", "")


def _exclude_selectors_for_variant(theme: dict, variant: str) -> set:

    filename = theme.get("variant_files", {}).get(variant)
    selectors = {
        variant.lower(),
        variant.lower().replace("_", ""),
    }
    if not filename:
        return selectors

    basename = os.path.basename(filename.replace("\\", "/")).lower()
    selectors.update({
        basename,
        _compact_filename_stem(filename),
    })
    return selectors


def resolve_excluded_variant_list(theme: dict, selectors: list, *, context: str, warn_unknown: bool = True) -> list:


    excluded = []
    seen = set()
    unknown = []

    for selector in selectors:
        key = selector.strip().lower()
        matches = [
            variant for variant in theme.get("variant_order", [])
            if key in _exclude_selectors_for_variant(theme, variant)
        ]
        if matches:
            variant = matches[0]
            if variant not in seen:
                excluded.append(variant)
                seen.add(variant)
        else:
            unknown.append(selector)

    if warn_unknown and unknown:
        print(
            f"[WARN] {context}: exclude selector non riconosciuti: "
            f"{', '.join(unknown)}"
        )

    return excluded


def resolve_excluded_variants(theme: dict, selectors: list, *, context: str) -> set:

    return set(resolve_excluded_variant_list(theme, selectors, context=context))


def resolve_excluded_variant_list_quiet(theme: dict, selectors: list) -> list:

    return resolve_excluded_variant_list(theme, selectors, context="", warn_unknown=False)


def warn_unmatched_exclude_selectors(selectors: list, themes: list) -> None:

    unknown = unmatched_exclude_selectors(selectors, themes)
    if unknown:
        print(
            "[WARN] exclude selector non riconosciuti: "
            f"{', '.join(unknown)}"
        )


def unmatched_exclude_selectors(selectors: list, themes: list) -> list:

    unknown = []
    for selector in selectors:
        key = selector.strip().lower()
        matched = any(
            key in _exclude_selectors_for_variant(theme, variant)
            for theme in themes
            for variant in theme.get("variant_order", [])
        )
        if not matched:
            unknown.append(selector)
    return unknown


def _variant_dir_identifier(theme: dict, variant: str) -> str:

    filename = theme.get("variant_files", {}).get(variant)
    if filename:
        basename = os.path.basename(filename.replace("\\", "/"))
        stem, _ = os.path.splitext(basename)
        for prefix in ("BSP_",):
            if stem.startswith(prefix):
                stem = stem[len(prefix):]
                break
        return stem.lower()
    return variant.lower()


def exclusion_dir_name(theme: dict, excluded_variants: set, ordered_variants=None) -> str:

    if not excluded_variants:
        return "standard"

    if ordered_variants:
        ordered = [variant for variant in ordered_variants if variant in excluded_variants]
        ordered.extend(sorted(excluded_variants - set(ordered)))
    else:
        ordered = [
            variant for variant in theme.get("variant_order", [])
            if variant in excluded_variants
        ]
        ordered.extend(sorted(excluded_variants - set(ordered)))
    identifiers = []
    seen_identifiers = set()
    for variant in ordered:
        identifier = _variant_dir_identifier(theme, variant)
        if identifier not in seen_identifiers:
            identifiers.append(identifier)
            seen_identifiers.add(identifier)
    return "-".join(
        f"no_{identifier}"
        for identifier in identifiers
    )


def exclusion_display_names(theme: dict, excluded_variants: list) -> list:

    names = []
    seen_names = set()
    for variant in excluded_variants:
        name = _variant_dir_identifier(theme, variant)
        if name not in seen_names:
            names.append(name)
            seen_names.add(name)
    return names


def _filtered_theme(theme: dict, excluded_variants: set):

    filtered = theme.copy()
    filtered["variant_order"] = [
        variant for variant in theme["variant_order"]
        if variant not in excluded_variants
    ]
    filtered.pop("focused_exclude_variants", None)
    filtered.pop("focused_title_suffix", None)
    return filtered


def _filtered_stats(stats: dict, excluded_variants: set):

    return {
        variant: data
        for variant, data in stats.items()
        if variant not in excluded_variants
    }


def generate_graphs(
    stats: dict,
    graphs_dir: str,
    theme: dict,
    title_suffix: str = "",
    *,
    include_focused: bool = True,
):

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import numpy as np
    except ImportError:
        print("Matplotlib is not installed. To enable plotting: pip install matplotlib numpy")
        sys.exit(1)

    os.makedirs(graphs_dir, exist_ok=True)

    labels = theme["variant_labels"]
    colors = theme["variant_colors"]
    markers = theme["variant_markers"]
    xlabel = theme["xlabel"]
    baseline = theme["baseline"]


    plt.rcParams.update({
        "font.family": "sans-serif",
        "font.size": 10,
        "axes.titlesize": 12,
        "axes.titleweight": "bold",
        "axes.labelsize": 10,
        "legend.fontsize": 9,
        "figure.facecolor": "white",
        "axes.facecolor": "#FAFAFA",
        "axes.grid": True,
        "grid.alpha": 0.3,
        "grid.linestyle": "--",
    })

    n_plots = len(MAIN_PLOT_LAYOUT)
    n_cols = 2
    n_rows = (n_plots + n_cols - 1) // n_cols

    fig, axes = plt.subplots(n_rows, n_cols, figsize=(14, 4.8 * n_rows))
    axes_flat = axes.flatten()

    variants = _ordered_variants(stats, theme)
    shared_metric_ylims = _shared_y_scale_limits_by_metric(stats, theme)

    for idx, config in enumerate(MAIN_PLOT_LAYOUT):
        ax = axes_flat[idx]
        if config is None:
            ax.axis("off")
            continue
        if "kind" in config:
            _plot_interpretive_chart_on_axis(
                ax=ax,
                stats=stats,
                theme=theme,
                config=config,
                xlabel=xlabel,
                compact=True,
            )
            continue

        metric = config["metric"]
        has_data = False
        series = []

        for variant in variants:
            if not _include_variant_for_metric(stats, variant, metric, theme):
                continue
            if metric not in stats[variant]:
                continue

            data = stats[variant][metric]
            if not data["n"]:
                continue

            series.append({
                "key": variant,
                "variant": variant,
                "x": np.array(data["n"]),
                "y": np.array(data["mean"]),
                "gc": np.array(data["gc"]),
                "color": colors.get(variant, None),
                "label": labels.get(variant, variant),
                "marker": markers.get(variant, "o"),
                "linestyle": _variant_linestyle(variant, theme),
            })

        offsets = _display_offsets_for_metric(metric, series)

        for item in series:
            has_data = True
            n = item["x"]
            mean = item["y"]
            gc = item["gc"]
            color = item["color"]
            transform = _offset_data_transform(ax, offsets.get(item["key"], 0.0))

            ax.plot(n, mean, marker=item["marker"], label=item["label"], color=color,
                    linestyle=item["linestyle"], linewidth=1.8, markersize=5,
                    markeredgecolor="white", markeredgewidth=0.7,
                    transform=transform, zorder=3)
            ax.fill_between(n, mean - gc, mean + gc,
                            alpha=VARIANT_FILL_ALPHA, color=color,
                            transform=transform, zorder=2)

        if metric in shared_metric_ylims:
            ax.set_ylim(*shared_metric_ylims[metric])
        else:
            _expand_flat_integer_axis(ax, series, metric)
        if metric in ENDPOINT_LABEL_METRICS:
            ax.margins(x=0.12)
            _annotate_metric_endpoints(ax, series, theme, metric, visual_offsets=offsets)
        else:
            _annotate_overlap_endpoints(
                ax,
                series,
                offsets,
                label_fn=lambda item: _endpoint_label(theme, item["variant"]),
            )
        if _has_visual_offsets(offsets) and metric not in ENDPOINT_LABEL_METRICS:
            ax.margins(x=0.05)

        ax.set_title(_format_title(metric, config["title"]))
        ax.set_xlabel(xlabel)
        ax.set_ylabel(config["ylabel"])
        if has_data:
            ax.legend(loc="upper left")

        _apply_y_axis_format(ax, metric)

        if _has_visual_offsets(offsets):
            _add_axis_caption(
                ax,
                OVERLAP_CAPTION,
                y=-0.23,
                width=66,
                fontsize=7,
            )

        if not has_data:
            ax.text(0.5, 0.5, "No data", transform=ax.transAxes,
                    ha="center", va="center", fontsize=14, color="#CCC")

    for ax in axes_flat[n_plots:]:
        ax.axis("off")

    suptitle = theme.get("suptitle", "Benchmark Results")
    if title_suffix:
        suptitle += f" — {title_suffix}"
    suptitle += f"\n(mean ± σ over {_detect_seeds(stats)} seeds per point)"

    fig.suptitle(suptitle, fontsize=14, fontweight="bold", y=0.98)
    plt.tight_layout(rect=[0, 0.01, 1, 0.955], h_pad=3.4, w_pad=3.8)
    _add_subplot_separators(fig, axes, n_plots)

    suffix = _filename_suffix(title_suffix)
    out_path = os.path.join(graphs_dir, f"benchmark_results{suffix}.png")
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Main chart saved to '{out_path}'.")


    for cfg in PLOT_CONFIGS:
        name, ext = os.path.splitext(cfg["filename"])
        fname = f"{name}{suffix}{ext}" if title_suffix else cfg["filename"]
        _generate_single_chart(
            stats=stats,
            graphs_dir=graphs_dir,
            metric=cfg["metric"],
            title=_format_title(cfg["metric"], cfg["title"]),
            ylabel=cfg["ylabel"],
            description=cfg["description"],
            filename=fname,
            theme=theme,
            xlabel=xlabel,
        )

    for cfg in INTERPRETIVE_PLOT_CONFIGS:
        name, ext = os.path.splitext(cfg["filename"])
        fname = f"{name}{suffix}{ext}" if title_suffix else cfg["filename"]
        _generate_interpretive_chart(
            stats=stats,
            graphs_dir=graphs_dir,
            config=cfg,
            filename=fname,
            theme=theme,
            xlabel=xlabel,
        )

    rel_fname = f"comparison_vs_{baseline}{suffix}.png" if title_suffix else f"comparison_vs_{baseline}.png"
    _generate_relative_vs_baseline_chart(stats, graphs_dir, baseline, theme, rel_fname, xlabel)

    ratio_fname = f"heuristics_vs_facts{suffix}.png" if title_suffix else "heuristics_vs_facts.png"
    _generate_heuristics_vs_facts_chart(stats, graphs_dir, theme, ratio_fname, xlabel)

    heuristic_baseline = theme.get("heuristic_baseline", baseline)
    reduction_fname = (
        f"heuristic_grounding_reduction_vs_{heuristic_baseline}{suffix}.png"
        if title_suffix else
        f"heuristic_grounding_reduction_vs_{heuristic_baseline}.png"
    )
    _generate_heuristic_reduction_chart(stats, graphs_dir, heuristic_baseline, theme, reduction_fname, xlabel)

    if include_focused and theme.get("focused_exclude_variants"):
        excluded = set(theme["focused_exclude_variants"])
        focused_stats = _filtered_stats(stats, excluded)
        if focused_stats:
            focused_theme = _filtered_theme(theme, excluded)
            focused_suffix = theme.get("focused_title_suffix", "focused")
            if title_suffix:
                focused_suffix = f"{title_suffix} {focused_suffix}"
            print(
                "  Generating focused charts without "
                f"{', '.join(sorted(excluded))}..."
            )
            generate_graphs(
                focused_stats,
                graphs_dir,
                focused_theme,
                title_suffix=focused_suffix,
                include_focused=False,
            )


def _generate_single_chart(stats, graphs_dir, metric, title, ylabel, description, filename, theme, xlabel):

    try:
        import matplotlib.pyplot as plt
        import numpy as np
    except ImportError:
        return

    labels = theme["variant_labels"]
    colors = theme["variant_colors"]
    markers_map = theme["variant_markers"]

    fig, ax = plt.subplots(figsize=(8, 5))
    variants = _ordered_variants(stats, theme)
    shared_metric_ylims = _shared_y_scale_limits_by_metric(stats, theme)
    has_data = False
    series = []

    for variant in variants:
        if not _include_variant_for_metric(stats, variant, metric, theme):
            continue
        if metric not in stats[variant]:
            continue
        data = stats[variant][metric]
        if not data["n"]:
            continue

        series.append({
            "key": variant,
            "variant": variant,
            "x": np.array(data["n"]),
            "y": np.array(data["mean"]),
            "gc": np.array(data["gc"]),
            "color": colors.get(variant, None),
            "label": labels.get(variant, variant),
            "marker": markers_map.get(variant, "o"),
            "linestyle": _variant_linestyle(variant, theme),
        })

    offsets = _display_offsets_for_metric(metric, series)

    for item in series:
        has_data = True
        n = item["x"]
        mean = item["y"]
        gc = item["gc"]
        color = item["color"]
        transform = _offset_data_transform(ax, offsets.get(item["key"], 0.0))

        ax.plot(n, mean, marker=item["marker"], label=item["label"], color=color,
                linestyle=item["linestyle"], linewidth=2, markersize=6,
                markeredgecolor="white", markeredgewidth=0.8,
                transform=transform, zorder=3)
        ax.fill_between(n, mean - gc, mean + gc,
                        alpha=VARIANT_FILL_ALPHA, color=color,
                        transform=transform, zorder=2)

    if metric in shared_metric_ylims:
        ax.set_ylim(*shared_metric_ylims[metric])
    else:
        _expand_flat_integer_axis(ax, series, metric)
    if metric in ENDPOINT_LABEL_METRICS:
        ax.margins(x=0.12)
        _annotate_metric_endpoints(ax, series, theme, metric, visual_offsets=offsets)
    else:
        _annotate_overlap_endpoints(
            ax,
            series,
            offsets,
            label_fn=lambda item: _endpoint_label(theme, item["variant"]),
        )
    if _has_visual_offsets(offsets) and metric not in ENDPOINT_LABEL_METRICS:
        ax.margins(x=0.05)

    ax.set_title(title, fontsize=13, fontweight="bold")
    ax.set_xlabel(xlabel, fontsize=11)
    ax.set_ylabel(ylabel, fontsize=11)
    if has_data:
        ax.legend(fontsize=10)
    else:
        ax.text(0.5, 0.5, "No data", transform=ax.transAxes,
                ha="center", va="center", fontsize=13, color="#AAA")
    ax.grid(True, alpha=0.3, linestyle="--")
    _apply_y_axis_format(ax, metric)

    _add_axis_caption(
        ax,
        _caption_with_overlap_note(description, offsets),
        y=-0.20,
        width=88,
        fontsize=8,
    )

    plt.tight_layout(rect=[0, 0.05, 1, 1])
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Chart '{filename}' saved to '{out_path}'.")


def _generate_interpretive_chart(stats, graphs_dir, config, filename, theme, xlabel):

    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return

    fig, ax = plt.subplots(figsize=(8.8, 5.2))
    _plot_interpretive_chart_on_axis(
        ax=ax,
        stats=stats,
        theme=theme,
        config=config,
        xlabel=xlabel,
        compact=False,
    )
    _add_axis_caption(
        ax,
        config["description"],
        y=-0.20,
        width=92,
        fontsize=8,
    )

    plt.tight_layout(rect=[0, 0.05, 1, 1])
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Chart '{filename}' saved to '{out_path}'.")


def _plot_interpretive_chart_on_axis(ax, stats, theme, config, xlabel, *, compact: bool):

    kind = config["kind"]
    if kind == "grounding_time_vs_heuristic_size":
        has_data = _plot_grounding_time_vs_heuristic_size(ax, stats, theme)
    elif kind == "lazy_standard_solving_time_ratio":
        has_data = _plot_lazy_standard_solving_time_ratio(ax, stats, theme)
    else:
        has_data = False

    ax.set_title(config["title"], fontsize=12 if compact else 13, fontweight="bold")
    ax.set_xlabel(config.get("xlabel", xlabel), fontsize=10 if compact else 11)
    ax.set_ylabel(config["ylabel"], fontsize=10 if compact else 11)
    ax.grid(True, alpha=0.3, linestyle="--")

    if has_data:
        ax.legend(fontsize=8 if compact else 9)
    else:
        ax.text(
            0.5,
            0.5,
            "No comparable data",
            transform=ax.transAxes,
            ha="center",
            va="center",
            fontsize=12,
            color="#AAA",
        )


def _plot_grounding_time_vs_heuristic_size(ax, stats, theme) -> bool:

    has_data = False
    series = []
    for variant in _ordered_variants(stats, theme):
        heuristic_size = _effective_heuristic_map(stats, variant)
        grounding = _metric_mean_map(stats, variant, "grounding_s")
        common_n = sorted(set(heuristic_size.keys()) & set(grounding.keys()))
        x_vals = []
        y_vals = []
        for n in common_n:
            x = heuristic_size[n]
            y = grounding[n]
            if x > 0 and y > 0:
                x_vals.append(x)
                y_vals.append(y)

        if not x_vals:
            continue

        has_data = True
        ax.scatter(
            x_vals,
            y_vals,
            marker=theme["variant_markers"].get(variant, "o"),
            s=42,
            color=theme["variant_colors"].get(variant),
            edgecolors="white",
            linewidths=0.7,
            alpha=0.92,
            label=theme["variant_labels"].get(variant, variant),
        )
        series.append({
            "key": variant,
            "variant": variant,
            "x": x_vals,
            "y": y_vals,
            "color": theme["variant_colors"].get(variant),
        })

    if has_data:
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.margins(x=0.12)
        _annotate_series_endpoints(
            ax,
            series,
            label_fn=lambda item: _endpoint_label(theme, item["variant"]),
        )
    return has_data


def _plot_lazy_standard_solving_time_ratio(ax, stats, theme) -> bool:

    has_data = False
    pairs = _available_lazy_standard_solving_time_ratio_pairs(stats, theme)
    series = []
    all_n_vals = []
    for standard, lazy in pairs:
        n_vals = _lazy_standard_solving_time_ratio_ns(stats, standard, lazy)
        if not n_vals:
            continue
        standard_map = _metric_mean_map(stats, standard, "solving_s")
        lazy_map = _metric_mean_map(stats, lazy, "solving_s")
        ratios = [
            _positive_ratio(lazy_map[n], standard_map[n])
            for n in n_vals
        ]
        if not _has_positive_finite(ratios):
            continue

        has_data = True
        ax.plot(
            n_vals,
            ratios,
            marker=theme["variant_markers"].get(lazy, "o"),
            linewidth=2,
            color=theme["variant_colors"].get(lazy),
            linestyle="-",
            markeredgecolor="white",
            markeredgewidth=0.8,
            label=f"{_variant_dir_identifier(theme, lazy)} / {_variant_dir_identifier(theme, standard)}",
        )
        series.append({
            "key": (standard, lazy),
            "variant": lazy,
            "standard": standard,
            "x": n_vals,
            "y": ratios,
            "color": theme["variant_colors"].get(lazy),
        })
        all_n_vals.extend(n_vals)

    ax.axhline(1.0, color="#555", linewidth=1, linestyle="--")
    if has_data:
        ax.set_yscale("log")
        ax.set_xlim(min(all_n_vals), max(all_n_vals))
        ax.margins(x=0.12)
        _annotate_series_endpoints(
            ax,
            series,
            label_fn=lambda item: (
                f"{_endpoint_label(theme, item['variant'])}/"
                f"{_endpoint_label(theme, item['standard'])}"
            ),
        )
    return has_data


def _lazy_standard_solving_time_ratio_ns(stats, standard, lazy):

    import math

    standard_map = _metric_mean_map(stats, standard, "solving_s")
    lazy_map = _metric_mean_map(stats, lazy, "solving_s")
    valid_n = {
        n
        for n in set(standard_map.keys()) & set(lazy_map.keys())
        if (
            math.isfinite(ratio := _positive_ratio(lazy_map[n], standard_map[n]))
            and ratio > 0
        )
    }

    return sorted(valid_n)


def _available_lazy_standard_solving_time_ratio_pairs(stats, theme):

    configured = theme.get("lazy_standard_solving_time_ratio_pairs")
    if configured is None:
        configured = [
            (standard, lazy)
            for standard, lazy, _ in theme.get("comparison_pairs", [])
        ]

    pairs = []
    for standard, lazy in configured:
        if standard in stats and lazy in stats:
            pairs.append((standard, lazy))
    return pairs


def _available_comparison_pairs(stats, theme):

    pairs = []
    for standard, lazy, label in theme.get("comparison_pairs", []):
        if standard in stats and lazy in stats:
            pairs.append((standard, lazy, label))
    return pairs


def _aligned_cross_metric_pair(stats, left_variant, left_metric, right_variant, right_metric):

    left_map = _metric_mean_map(stats, left_variant, left_metric)
    right_map = _metric_mean_map(stats, right_variant, right_metric)
    common_n = sorted(set(left_map.keys()) & set(right_map.keys()))
    return common_n, [left_map[n] for n in common_n], [right_map[n] for n in common_n]


def _positive_ratio(numerator, denominator):

    if denominator <= 0 or numerator <= 0:
        return float("nan")
    return numerator / denominator


def _has_finite(values) -> bool:

    import math

    return any(math.isfinite(float(value)) for value in values)


def _has_positive_finite(values) -> bool:

    import math

    return any(math.isfinite(float(value)) and value > 0 for value in values)


def _apply_compact_axis_formatter(ax):

    from matplotlib.ticker import FuncFormatter, MaxNLocator

    ax.yaxis.set_major_locator(MaxNLocator(nbins=6))
    ax.yaxis.set_major_formatter(FuncFormatter(_format_compact_number))
    ax.yaxis.offsetText.set_visible(False)


def _generate_relative_vs_baseline_chart(stats, graphs_dir, baseline_variant, theme, filename, xlabel):

    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return

    labels = theme["variant_labels"]
    colors = theme["variant_colors"]
    markers_map = theme["variant_markers"]

    if baseline_variant not in stats:
        print(f"  Relative chart skipped: baseline '{baseline_variant}' not found.")
        return

    variants = [v for v in _ordered_variants(stats, theme) if v != baseline_variant]
    if not variants:
        print("  Relative chart skipped: no non-baseline variants available.")
        return

    fig, axes = plt.subplots(2, 1, figsize=(9, 8), sharex=True)
    ax_speedup, ax_reduction = axes
    has_positive_speedup = False
    speedup_series = []


    for variant in variants:
        n_vals, base_total, var_total = _aligned_metric_pair(stats, baseline_variant, variant, "total_s")
        if not n_vals:
            continue

        speedup = []
        for b, v in zip(base_total, var_total):
            if v <= 0:
                speedup.append(float("nan"))
            else:
                s = b / v
                speedup.append(s)
                if s > 0:
                    has_positive_speedup = True

        speedup_series.append({
            "key": ("speedup", variant),
            "variant": variant,
            "x": n_vals,
            "y": speedup,
            "color": colors.get(variant),
            "label": labels.get(variant, variant),
            "marker": markers_map.get(variant, "o"),
            "linestyle": _variant_linestyle(variant, theme),
        })

    speedup_offsets = _display_offsets_for_series(speedup_series, enabled=False)
    for item in speedup_series:
        transform = _offset_data_transform(ax_speedup, speedup_offsets.get(item["key"], 0.0))
        ax_speedup.plot(item["x"], item["y"], marker=item["marker"], linewidth=2,
                        color=item["color"], linestyle=item["linestyle"],
                        markeredgecolor="white", markeredgewidth=0.8,
                        transform=transform, label=item["label"])

    ax_speedup.axhline(1.0, color="#555", linewidth=1, linestyle="--")
    ax_speedup.set_title(f"Total Time Speedup vs {labels.get(baseline_variant, baseline_variant)}")
    if has_positive_speedup:
        ax_speedup.set_yscale("log")
        ax_speedup.set_ylabel("Speedup (x, log scale)")
    else:
        ax_speedup.set_ylabel("Speedup (x)")
    ax_speedup.grid(True, alpha=0.3, linestyle="--")
    ax_speedup.legend(fontsize=9)
    total_domain = _all_metric_ns(stats, ["total_s"])
    if total_domain:
        ax_speedup.set_xlim(min(total_domain), max(total_domain))
    ax_speedup.margins(x=0.12)
    _annotate_series_endpoints(
        ax_speedup,
        speedup_series,
        label_fn=lambda item: _endpoint_label(theme, item["variant"]),
        visual_offsets=speedup_offsets,
    )
    if _has_visual_offsets(speedup_offsets):
        ax_speedup.margins(x=0.05)

    reduction_series = []

    for variant in variants:
        color = colors.get(variant)
        marker = markers_map.get(variant, "o")
        pretty = labels.get(variant, variant)

        size_metric = _preferred_ground_size_metric(stats, baseline_variant, variant)
        n_size, base_size, var_size = _aligned_metric_pair(stats, baseline_variant, variant, size_metric)
        if n_size:
            red_size = [100.0 * (b - v) / b if b != 0 else float("nan")
                        for b, v in zip(base_size, var_size)]
            size_label = "ground lines" if size_metric == "ground_lines" else "solver rules"
            reduction_series.append({
                "key": ("size", variant),
                "variant": variant,
                "kind": "size",
                "x": n_size,
                "y": red_size,
                "color": color,
                "label": f"{pretty} - {size_label}",
                "marker": marker,
                "linestyle": "-",
            })

        n_vars, base_vars, var_vars = _aligned_metric_pair(stats, baseline_variant, variant, "variables")
        if n_vars:
            red_vars = [100.0 * (b - v) / b if b != 0 else float("nan")
                        for b, v in zip(base_vars, var_vars)]
            reduction_series.append({
                "key": ("variables", variant),
                "variant": variant,
                "kind": "vars",
                "x": n_vars,
                "y": red_vars,
                "color": color,
                "label": f"{pretty} - variables",
                "marker": marker,
                "linestyle": ":",
            })

    reduction_offsets = _display_offsets_for_series(reduction_series, enabled=False)
    for item in reduction_series:
        transform = _offset_data_transform(ax_reduction, reduction_offsets.get(item["key"], 0.0))
        ax_reduction.plot(item["x"], item["y"], marker=item["marker"], linewidth=2,
                          color=item["color"], linestyle=item["linestyle"],
                          markeredgecolor="white", markeredgewidth=0.8,
                          transform=transform, label=item["label"])

    ax_reduction.margins(x=0.12)
    _annotate_series_endpoints(
        ax_reduction,
        reduction_series,
        label_fn=lambda item: f"{_endpoint_label(theme, item['variant'])} {item['kind']}",
        visual_offsets=reduction_offsets,
    )
    if _has_visual_offsets(reduction_offsets):
        ax_reduction.margins(x=0.05)

    ax_reduction.axhline(0.0, color="#555", linewidth=1, linestyle="--")
    ax_reduction.set_title("Ground Program Size Reduction vs Baseline")
    ax_reduction.set_xlabel(xlabel)
    ax_reduction.set_ylabel("Reduction (%)")
    ax_reduction.grid(True, alpha=0.3, linestyle="--")
    ax_reduction.legend(fontsize=8, ncol=2)
    reduction_domain = _all_metric_ns(stats, ["rules", "ground_lines", "variables"])
    if reduction_domain:
        ax_reduction.set_xlim(min(reduction_domain), max(reduction_domain))

    plt.tight_layout()
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Chart '{filename}' saved to '{out_path}'.")


def _metric_mean_map(stats, variant, metric):

    if metric not in stats.get(variant, {}):
        return {}
    data = stats[variant][metric]
    return dict(zip(data["n"], data["mean"]))


def _all_metric_ns(stats, metrics):

    ns = set()
    for variant_data in stats.values():
        for metric in metrics:
            if metric in variant_data:
                ns.update(variant_data[metric]["n"])
    return sorted(ns)


def _effective_heuristic_map(stats, variant):


    native = _metric_mean_map(stats, variant, "ground_heuristics")
    lazy = _metric_mean_map(stats, variant, "ground_lazy_heuristic_facts")
    ns = sorted(set(native.keys()) | set(lazy.keys()))
    return {n: native.get(n, 0.0) + lazy.get(n, 0.0) for n in ns}


def _generate_heuristics_vs_facts_chart(stats, graphs_dir, theme, filename, xlabel):

    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return

    labels = theme["variant_labels"]
    colors = theme["variant_colors"]
    markers_map = theme["variant_markers"]

    fig, ax = plt.subplots(figsize=(9, 5.4))
    has_data = False
    series = []

    for variant in _ordered_variants(stats, theme):
        facts = _metric_mean_map(stats, variant, "ground_facts")
        native = _metric_mean_map(stats, variant, "ground_heuristics")
        lazy = _metric_mean_map(stats, variant, "ground_lazy_heuristic_facts")
        common_n = sorted(set(facts.keys()) & (set(native.keys()) | set(lazy.keys())))
        if not common_n:
            continue

        native_ratio = []
        lazy_ratio = []
        for n in common_n:
            other_facts = max(facts.get(n, 0.0) - lazy.get(n, 0.0), 1.0)
            n_ratio = 100.0 * native.get(n, 0.0) / other_facts
            l_ratio = 100.0 * lazy.get(n, 0.0) / other_facts
            native_ratio.append(n_ratio if n_ratio > 0 else float("nan"))
            lazy_ratio.append(l_ratio if l_ratio > 0 else float("nan"))

        color = colors.get(variant)
        marker = markers_map.get(variant, "o")
        pretty = labels.get(variant, variant)

        if any(v == v and v > 0 for v in native_ratio):
            has_data = True
            series.append({
                "key": ("native", variant),
                "variant": variant,
                "kind": "#h",
                "x": common_n,
                "y": native_ratio,
                "color": color,
                "label": f"{pretty} - #heuristic/other facts",
                "marker": marker,
                "linestyle": "-",
            })
        if any(v == v and v > 0 for v in lazy_ratio):
            has_data = True
            series.append({
                "key": ("lazy", variant),
                "variant": variant,
                "kind": "lazy",
                "x": common_n,
                "y": lazy_ratio,
                "color": color,
                "label": f"{pretty} - __heuristic facts/other facts",
                "marker": marker,
                "linestyle": ":",
            })

    offsets = _display_offsets_for_series(series, enabled=False)
    for item in series:
        transform = _offset_data_transform(ax, offsets.get(item["key"], 0.0))
        ax.plot(item["x"], item["y"], marker=item["marker"], linewidth=2,
                color=item["color"], linestyle=item["linestyle"],
                markeredgecolor="white", markeredgewidth=0.8,
                transform=transform, label=item["label"])

    ax.set_title("Heuristic Grounding Weight vs Other Facts", fontsize=13, fontweight="bold")
    ax.set_xlabel(xlabel, fontsize=11)
    ax.set_ylabel("Ratio (%)")
    ax.grid(True, alpha=0.3, linestyle="--")
    if has_data:
        ax.set_yscale("log")
        ax.margins(x=0.12)
        _annotate_series_endpoints(
            ax,
            series,
            label_fn=lambda item: f"{_endpoint_label(theme, item['variant'])} {item['kind']}",
            visual_offsets=offsets,
        )
        if _has_visual_offsets(offsets):
            ax.margins(x=0.05)
        ax.legend(fontsize=8, ncol=1)
    else:
        ax.text(0.5, 0.5, "No heuristic/fact data", transform=ax.transAxes,
                ha="center", va="center", fontsize=13, color="#AAA")

    if _has_visual_offsets(offsets):
        fig.text(0.5, 0.01, OVERLAP_CAPTION, ha="center", va="bottom",
                 fontsize=8, color=CAPTION_COLOR, fontstyle="italic")
        plt.tight_layout(rect=[0, 0.04, 1, 1])
    else:
        plt.tight_layout()
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Chart '{filename}' saved to '{out_path}'.")


def _generate_heuristic_reduction_chart(stats, graphs_dir, baseline_variant, theme, filename, xlabel):

    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return

    baseline = _effective_heuristic_map(stats, baseline_variant)
    if not baseline:
        print(f"  Heuristic reduction chart skipped: baseline '{baseline_variant}' has no heuristic counts.")
        return

    labels = theme["variant_labels"]
    colors = theme["variant_colors"]
    markers_map = theme["variant_markers"]

    fig, ax = plt.subplots(figsize=(8.5, 5))
    has_data = False
    series = []

    for variant in [v for v in _ordered_variants(stats, theme) if v != baseline_variant]:
        current = _effective_heuristic_map(stats, variant)
        common_n = sorted(set(baseline.keys()) & set(current.keys()))
        if not common_n:
            continue

        reduction = [
            100.0 * (baseline[n] - current[n]) / baseline[n]
            if baseline[n] > 0 else float("nan")
            for n in common_n
        ]
        if not reduction:
            continue

        has_data = True
        series.append({
            "key": variant,
            "variant": variant,
            "x": common_n,
            "y": reduction,
            "color": colors.get(variant),
            "label": labels.get(variant, variant),
            "marker": markers_map.get(variant, "o"),
            "linestyle": _variant_linestyle(variant, theme),
        })

    offsets = _display_offsets_for_series(series, enabled=False)
    for item in series:
        transform = _offset_data_transform(ax, offsets.get(item["key"], 0.0))
        ax.plot(item["x"], item["y"],
                marker=item["marker"],
                linewidth=2,
                color=item["color"],
                linestyle=item["linestyle"],
                markeredgecolor="white",
                markeredgewidth=0.8,
                transform=transform,
                label=item["label"])

    ax.margins(x=0.12)
    _annotate_series_endpoints(
        ax,
        series,
        label_fn=lambda item: _endpoint_label(theme, item["variant"]),
        visual_offsets=offsets,
    )
    if _has_visual_offsets(offsets):
        ax.margins(x=0.05)

    ax.axhline(0.0, color="#555", linewidth=1, linestyle="--")
    ax.set_title(f"Heuristic Grounding Reduction vs {labels.get(baseline_variant, baseline_variant)}",
                 fontsize=13, fontweight="bold")
    ax.set_xlabel(xlabel, fontsize=11)
    ax.set_ylabel("Reduction (%)")
    ax.grid(True, alpha=0.3, linestyle="--")
    heuristic_domain = _all_metric_ns(stats, ["ground_heuristics", "ground_lazy_heuristic_facts"])
    if heuristic_domain:
        ax.set_xlim(min(heuristic_domain), max(heuristic_domain))
    if has_data:
        ax.legend(fontsize=9)
    else:
        ax.text(0.5, 0.5, "No comparable heuristic counts", transform=ax.transAxes,
                ha="center", va="center", fontsize=13, color="#AAA")

    if _has_visual_offsets(offsets):
        fig.text(0.5, 0.01, OVERLAP_CAPTION, ha="center", va="bottom",
                 fontsize=8, color=CAPTION_COLOR, fontstyle="italic")
        plt.tight_layout(rect=[0, 0.04, 1, 1])
    else:
        plt.tight_layout()
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Chart '{filename}' saved to '{out_path}'.")


def _aligned_metric_pair(stats, baseline_variant, variant, metric):

    if metric not in stats.get(baseline_variant, {}) or metric not in stats.get(variant, {}):
        return [], [], []

    base_data = stats[baseline_variant][metric]
    var_data = stats[variant][metric]

    base_map = dict(zip(base_data["n"], base_data["mean"]))
    var_map = dict(zip(var_data["n"], var_data["mean"]))

    common_n = sorted(set(base_map.keys()) & set(var_map.keys()))
    return common_n, [base_map[n] for n in common_n], [var_map[n] for n in common_n]


def _preferred_ground_size_metric(stats, baseline_variant, variant):

    if (
        "rules" in stats.get(baseline_variant, {}) and
        "rules" in stats.get(variant, {})
    ):
        return "rules"
    return "ground_lines"


def _detect_seeds(stats):

    counts = set()
    for variant in stats.values():
        for metric in variant.values():
            counts.update(metric.get("count", []))

    if not counts:
        return "?"
    if len(counts) == 1:
        return str(next(iter(counts)))
    return f"{min(counts)}-{max(counts)}"


def _detect_seeds_per_variant(raw):

    result = {}
    for variant, n_data in raw.items():
        counts = []
        for n_metrics in n_data.values():
            if "solving_s" in n_metrics:
                counts.append(len(n_metrics["solving_s"]))
            else:
                metric_lengths = [len(values) for values in n_metrics.values() if values]
                if metric_lengths:
                    counts.append(max(metric_lengths))

        if counts:
            unique = sorted(set(counts))
            if len(unique) == 1:
                result[variant] = str(unique[0])
            else:
                result[variant] = f"{unique[0]}-{unique[-1]}"
        else:
            result[variant] = "0"

    return result


def print_summary_table(stats, theme):

    variants = _ordered_variants(stats, theme)
    labels = theme["variant_labels"]
    table_width = 8 + len(variants) * 87

    print(f"\n{'='*table_width}")
    print(f"{'N':>5}  ", end="")
    for v in variants:
        label = labels.get(v, v)
        print(f"  {label:>35}", end="")
    print()
    print(f"{'':>5}  ", end="")
    for _ in variants:
        print(f"  {'Grnd(s)':>8} {'Solv(s)':>8} {'Tot(s)':>8} {'Choices':>8} {'Conf.':>8} {'Rst.':>6} {'MemGB':>7} {'Lines':>7} {'Rules':>7} {'Vars':>7} {'Heur':>7} {'LazyH':>7} {'Facts':>7}", end="")
    print()
    print("-" * table_width)

    all_ns = set()
    for v in variants:
        for metric_data in stats[v].values():
            all_ns.update(metric_data["n"])

    for n in sorted(all_ns):
        row = f"{n:>5}  "
        for v in variants:
            grounding = _get_mean_at_n(stats[v], "grounding_s", n)
            solving = _get_mean_at_n(stats[v], "solving_s", n)
            total = _get_mean_at_n(stats[v], "total_s", n)
            choices = _get_mean_at_n(stats[v], "choices", n)
            conflicts = _get_mean_at_n(stats[v], "conflicts", n)
            restarts = _get_mean_at_n(stats[v], "restarts", n)
            memory_mb = _get_mean_at_n(stats[v], "memory_mb", n)
            ground_lines = _get_mean_at_n(stats[v], "ground_lines", n)
            rules = _get_mean_at_n(stats[v], "rules", n)
            variables = _get_mean_at_n(stats[v], "variables", n)
            ground_heuristics = _get_mean_at_n(stats[v], "ground_heuristics", n)
            ground_lazy = _get_mean_at_n(stats[v], "ground_lazy_heuristic_facts", n)
            ground_facts = _get_mean_at_n(stats[v], "ground_facts", n)

            g_str = f"{grounding:.4f}" if grounding is not None else "N/A"
            s_str = f"{solving:.4f}" if solving is not None else "N/A"
            t_str = f"{total:.4f}" if total is not None else "N/A"
            c_str = f"{choices:.0f}" if choices is not None else "N/A"
            f_str = f"{conflicts:.0f}" if conflicts is not None else "N/A"
            rs_str = f"{restarts:.0f}" if restarts is not None else "N/A"
            m_str = f"{memory_mb / 1024:.2f}" if memory_mb is not None else "N/A"
            gl_str = f"{ground_lines:.0f}" if ground_lines is not None else "N/A"
            r_str = f"{rules:.0f}" if rules is not None else "N/A"
            v_str = f"{variables:.0f}" if variables is not None else "N/A"
            h_str = f"{ground_heuristics:.0f}" if ground_heuristics is not None else "N/A"
            lh_str = f"{ground_lazy:.0f}" if ground_lazy is not None else "N/A"
            gf_str = f"{ground_facts:.0f}" if ground_facts is not None else "N/A"

            row += f"  {g_str:>8} {s_str:>8} {t_str:>8} {c_str:>8} {f_str:>8} {rs_str:>6} {m_str:>7} {gl_str:>7} {r_str:>7} {v_str:>7} {h_str:>7} {lh_str:>7} {gf_str:>7}"
        print(row)

    print(f"{'='*table_width}\n")


def _get_mean_at_n(variant_stats, metric, n):

    if metric not in variant_stats:
        return None
    data = variant_stats[metric]
    if n in data["n"]:
        idx = data["n"].index(n)
        return data["mean"][idx]
    return None


def reset_graphs_dir(graphs_dir):

    graphs_dir = os.path.abspath(graphs_dir)
    cwd = os.path.abspath(os.getcwd())
    unsafe_paths = {os.path.abspath(os.sep), cwd, os.path.expanduser("~")}
    if graphs_dir in unsafe_paths:
        raise ValueError(f"Refusing to clean unsafe output directory: '{graphs_dir}'")

    if not os.path.isdir(graphs_dir):
        os.makedirs(graphs_dir, exist_ok=True)
        print(f"\nOutput grafici inizializzato: '{graphs_dir}'")
        return

    for entry in os.listdir(graphs_dir):
        path = os.path.join(graphs_dir, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)

    print(f"\nOutput grafici svuotato: '{graphs_dir}'")


def ensure_plot_dependencies():

    try:
        import matplotlib
        import numpy
    except ImportError:
        print("Matplotlib/Numpy non sono installati.")
        print("Crea un virtualenv e installa le dipendenze, ad esempio:")
        print("  python3 -m venv /tmp/clingo-graphs-venv")
        print(f"  /tmp/clingo-graphs-venv/bin/python -m pip install -r {os.path.join(TEST_ROOT, 'requirements.txt')}")
        print("  cd test_folder")
        print("  PYTHON_BIN=/tmp/clingo-graphs-venv/bin/python ./generate_graphs.sh")
        sys.exit(1)


# ==========================================================================
# Confronto native vs prolog (solo varianti lazy) -> graphs-native-prolog/
# ==========================================================================
COMPARE_METRICS = [
    ("total_s", "Total Time", "Time (seconds)"),
    ("solving_s", "Solving Time", "Time (seconds)"),
    ("grounding_s", "Grounding Time (proxy)", "Time (seconds)"),
    ("choices", "Choices", "Number of choices"),
    ("conflicts", "Conflicts", "Number of conflicts"),
    ("memory_mb", "RSS Memory", "Memory (GB)"),
    ("combined_heuristics", "Heuristic Grounding", "Ground heuristic entries"),
    ("prolog_ms_per_decide", "Prolog Query Cost / Decision", "ms per decision"),
]

# Stile per backend nel confronto: native linea piena, prolog tratteggiata.
COMPARE_BACKEND_STYLE = {
    "native": {"linestyle": "-", "fill": False, "alpha": 1.0},
    "prolog": {"linestyle": "--", "fill": True, "alpha": 0.9},
}


def load_stats(csv_path, theme):
    """Carica un CSV e ritorna stats ristrette alle varianti note del tema."""
    if not os.path.isfile(csv_path) or os.path.getsize(csv_path) == 0:
        return None
    raw = load_csv(csv_path)
    if not raw:
        return None
    stats = compute_stats(raw)
    known = set(theme.get("variant_order", []))
    return {v: data for v, data in stats.items() if v in known}


def _plot_compare_metric(ax, metric, stats_by_backend, lazy_variants, theme):
    import numpy as np

    colors = theme["variant_colors"]
    markers = theme["variant_markers"]
    labels = theme["variant_labels"]
    has_data = False

    for variant in lazy_variants:
        for backend, stats in stats_by_backend.items():
            data = stats.get(variant, {}).get(metric)
            if not data or not data["n"]:
                continue
            style = COMPARE_BACKEND_STYLE.get(backend, {"linestyle": "-", "fill": False})
            x = np.array(data["n"])
            mean = np.array(data["mean"])
            sd = np.array(data["gc"])
            color = colors.get(variant)
            ax.plot(
                x, mean,
                marker=markers.get(variant, "o"),
                markersize=5, markeredgecolor="white", markeredgewidth=0.7,
                linewidth=1.9, linestyle=style["linestyle"], color=color,
                label=f"{labels.get(variant, variant)} [{backend}]",
            )
            ax.fill_between(x, mean - sd, mean + sd, color=color,
                            alpha=VARIANT_FILL_ALPHA)
            has_data = True

    _apply_y_axis_format(ax, metric)
    return has_data


def generate_comparison_graphs(stats_by_backend, out_dir, theme, problem_label, lazy_variants):
    """Confronta le stesse varianti lazy tra backend native e prolog."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("Matplotlib non installato: salto i grafici di confronto.")
        return False

    present = {b: s for b, s in stats_by_backend.items() if s}
    if len(present) < 2:
        print(f"  [SKIP] confronto {problem_label}: servono entrambi i backend "
              f"(trovati: {', '.join(present) or 'nessuno'}).")
        return False

    ordered_lazy = [v for v in theme.get("variant_order", []) if v in lazy_variants]
    ordered_lazy = [
        v for v in ordered_lazy
        if any(v in present[b] for b in present)
    ]
    if not ordered_lazy:
        print(f"  [SKIP] confronto {problem_label}: nessuna variante lazy nei dati.")
        return False

    os.makedirs(out_dir, exist_ok=True)
    xlabel = theme.get("xlabel", "Problem size (N)")

    plt.rcParams.update({
        "font.family": "sans-serif", "font.size": 10,
        "figure.facecolor": "white", "axes.facecolor": "#FAFAFA",
        "axes.grid": True, "grid.alpha": 0.3, "grid.linestyle": "--",
    })

    n_cols = 2
    n_rows = (len(COMPARE_METRICS) + n_cols - 1) // n_cols
    fig, axes = plt.subplots(n_rows, n_cols, figsize=(14, 4.6 * n_rows))
    axes_flat = axes.flatten()

    for idx, (metric, title, ylabel) in enumerate(COMPARE_METRICS):
        ax = axes_flat[idx]
        has_data = _plot_compare_metric(ax, metric, present, ordered_lazy, theme)
        ax.set_title(_format_title(metric, title), fontsize=12, fontweight="bold")
        ax.set_xlabel(xlabel)
        ax.set_ylabel(ylabel)
        if has_data:
            ax.legend(fontsize=8, loc="best")
        else:
            ax.text(0.5, 0.5, "No data", transform=ax.transAxes,
                    ha="center", va="center", fontsize=13, color="#CCC")

    for ax in axes_flat[len(COMPARE_METRICS):]:
        ax.axis("off")

    fig.suptitle(
        f"{problem_label}: confronto backend Native vs Prolog (varianti lazy)\n"
        "linea piena = native, tratteggiata = prolog; banda = ±σ sui seed",
        fontsize=14, fontweight="bold", y=0.99,
    )
    plt.tight_layout(rect=[0, 0.01, 1, 0.95], h_pad=3.0, w_pad=3.0)
    main_path = os.path.join(out_dir, "comparison_native_vs_prolog.png")
    plt.savefig(main_path, dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(f"  Comparison chart saved to '{main_path}'.")

    # Singoli grafici per le metriche piu' importanti del confronto.
    for metric, title, ylabel in COMPARE_METRICS:
        fig, ax = plt.subplots(figsize=(8, 5))
        has_data = _plot_compare_metric(ax, metric, present, ordered_lazy, theme)
        ax.set_title(_format_title(metric, title), fontsize=13, fontweight="bold")
        ax.set_xlabel(xlabel, fontsize=11)
        ax.set_ylabel(ylabel, fontsize=11)
        if has_data:
            ax.legend(fontsize=9)
        else:
            ax.text(0.5, 0.5, "No data", transform=ax.transAxes,
                    ha="center", va="center", fontsize=13, color="#AAA")
        plt.tight_layout()
        out_path = os.path.join(out_dir, f"{metric}.png")
        plt.savefig(out_path, dpi=200, bbox_inches="tight")
        plt.close(fig)

    print(f"  Confronto {problem_label}: {len(COMPARE_METRICS)} metriche in '{out_dir}'.")
    return True


def process_csv(
    csv_path,
    graphs_dir,
    theme,
    problem_name,
    title_suffix="",
    excluded_variants=None,
    *,
    include_random_variability=False,
):

    if not os.path.isfile(csv_path):
        print(f"\n[SKIP] {problem_name}: CSV non trovato: '{csv_path}'")
        return False

    print(f"\n{'='*60}")
    print(f"  {problem_name}")
    print(f"  CSV:    {csv_path}")
    print(f"  Output: {graphs_dir}")
    print(f"{'='*60}")

    raw = load_csv(csv_path)
    if not raw:
        print(f"  [SKIP] CSV vuoto o senza dati validi.")
        return False

    print(f"  Varianti trovate: {list(raw.keys())}")
    seeds_per_variant = _detect_seeds_per_variant(raw)
    for variant, n_data in raw.items():
        ns = sorted(n_data.keys())
        seeds = seeds_per_variant.get(variant, "0")
        print(f"    {variant}: {len(ns)} N values, ~{seeds} seeds per point")

    stats = compute_stats(raw)
    known_variants = set(theme.get("variant_order", []))
    unsupported_variants = sorted(set(stats) - known_variants)
    if unsupported_variants:
        stats = {
            variant: data
            for variant, data in stats.items()
            if variant in known_variants
        }
        print(
            "  Varianti non piu' supportate ignorate: "
            f"{', '.join(unsupported_variants)}"
        )

    excluded_variants = set(excluded_variants or [])
    if excluded_variants:
        stats = _filtered_stats(stats, excluded_variants)
        theme = _filtered_theme(theme, excluded_variants)
        excluded_names = sorted(set(exclusion_display_names(theme, sorted(excluded_variants))))
        print(f"  Varianti escluse dai grafici: {', '.join(excluded_names)}")

    if not stats:
        print("  [SKIP] Nessuna variante rimasta dopo gli exclude.")
        return False

    print_summary_table(stats, theme)
    generate_graphs(stats, graphs_dir, theme, title_suffix=title_suffix)
    if include_random_variability:
        generate_random_variability_graphs(csv_path, graphs_dir, theme)
    return True


def _color(text: str, code: str) -> str:

    if not sys.stdout.isatty() or os.environ.get("NO_COLOR") or os.environ.get("TERM") == "dumb":
        return text
    return f"\033[{code}m{text}\033[0m"


def parse_args():
    heading = lambda text: _color(text, "1;36")
    cmd = lambda text: _color(text, "1;32")
    opt = lambda text: _color(text, "1;33")
    value = lambda text: _color(text, "35")

    parser = argparse.ArgumentParser(
        prog="gen_graphs.py",
        description="Genera i grafici BSP/PUP dai CSV per-backend (native/prolog).",
        epilog=f"""
{heading("Comandi")}
  {cmd("%(prog)s")}
      Genera tutto: BSP e PUP per ogni backend presente, piu' il confronto
      native-vs-prolog. Legge anche i CSV randomici se presenti.

  {cmd("%(prog)s --reset")}
      Svuota gli alberi grafici (graphs-native, graphs-prolog,
      graphs-native-prolog) ed esce. Unico comando che cancella file.

  {cmd("%(prog)s --backend native --type bsp")}
      Solo BSP, solo backend native.

  {cmd("%(prog)s --type compare")}
      Solo i grafici di confronto native-vs-prolog (varianti lazy).

{heading("CSV attesi")}
  {value("results-native/1_BSP_native.csv")}   BSP, backend native.
  {value("results-native/2_PUP_native.csv")}   PUP, backend native.
  {value("results-prolog/1_BSP_prolog.csv")}   BSP, backend prolog.
  {value("results-prolog/2_PUP_prolog.csv")}   PUP, backend prolog.
  {value("results-<b>/1_BSP_<b>_random.csv")}  BSP randomico/multi-seed.

{heading("Cartelle di output")}
  {value("graphs-native/1_BSP/")}            BSP, tutte le varianti, native.
  {value("graphs-native/2_PUP/")}            PUP, tutte le varianti, native.
  {value("graphs-prolog/1_BSP/")}            BSP, tutte le varianti, prolog.
  {value("graphs-prolog/2_PUP/")}            PUP, tutte le varianti, prolog.
  {value("graphs-native-prolog/1_BSP/")}     Confronto native-vs-prolog (lazy).
  {value("graphs-native-prolog/2_PUP/")}     Confronto native-vs-prolog (lazy).

{heading("Opzioni")}
  {opt("--backend {{native,prolog}}")}  Limita a un backend. Default: entrambi.
  {opt("--type {{bsp,pup,bsp_random,compare}}")}  Limita a una famiglia.
  {opt("--out-root DIR")}            Radice degli alberi grafici. Default: test_folder.
  {opt("--exclude SELECTOR")}        Esclude varianti (sottocartella no_<variante>).
  {opt("--reset")}                   Svuota gli alberi grafici ed esce.
        """.strip(),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--backend",
        choices=BACKENDS,
        default=None,
        help="Limita a un solo backend. Default: tutti quelli con CSV presenti.",
    )
    parser.add_argument(
        "--out-root",
        default=TEST_ROOT,
        metavar="DIR",
        help=f"Radice in cui creare graphs-<backend>/ e graphs-native-prolog/. Default: {TEST_ROOT}.",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        nargs="+",
        default=[],
        metavar="SELECTOR",
        help=(
            "Esclude varianti per la famiglia scelta. Accetta id variante "
            "(la, lc, ga, ...), nome file (BSP_lc.lp) o stem compatto. Ripetibile "
            "o separato da virgole."
        ),
    )
    parser.add_argument(
        "--type",
        choices=("bsp", "pup", "bsp_random", "compare"),
        default=None,
        help="Genera solo una famiglia. Senza --type vengono generati tutti i grafici.",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Svuota gli alberi grafici ed esce.",
    )

    args = parser.parse_args()
    exclude_selectors = _split_exclude_selectors(args.exclude)
    if args.reset and (args.type or exclude_selectors or args.backend):
        parser.error("--reset va usato da solo.")
    if exclude_selectors and args.type not in ("bsp", "pup"):
        parser.error("--exclude richiede --type bsp oppure --type pup.")
    return args


def build_themes():
    bsp_theme = BSP_THEME.copy()
    bsp_theme["suptitle"] = "BSP Benchmark: Standard vs Lazy Heuristic Grounding"
    pup_theme = PUP_THEME.copy()
    pup_theme["suptitle"] = "PUP Benchmark: Standard vs Lazy Heuristic Grounding"
    return bsp_theme, pup_theme


# Descrittore per problema: tema, template CSV, sottocartella, etichetta.
PROBLEM_SPECS = {
    "bsp": {"theme_index": 0, "csv": BSP_CSV_TMPL, "subdir": BSP_SUBDIR, "label": "BSP"},
    "pup": {"theme_index": 1, "csv": PUP_CSV_TMPL, "subdir": PUP_SUBDIR, "label": "PUP"},
}


def _theme_for(problem):
    bsp_theme, pup_theme = build_themes()
    return (bsp_theme, pup_theme)[PROBLEM_SPECS[problem]["theme_index"]]


def process_problem(backend, problem, exclude_selectors, out_root):
    spec = PROBLEM_SPECS[problem]
    theme = _theme_for(problem)
    csv_path = os.path.join(results_dir_for(backend), spec["csv"].format(backend=backend))

    excluded_order = resolve_excluded_variant_list_quiet(theme, exclude_selectors)
    excluded = set(excluded_order)
    out = os.path.join(out_root, f"graphs-{backend}", spec["subdir"])
    if excluded:
        out = os.path.join(out, exclusion_dir_name(theme, excluded, excluded_order))
    label = f"{spec['label']} [{backend}]"
    return process_csv(csv_path, out, theme, label, excluded_variants=excluded)


def process_bsp_random(backend, out_root):
    theme = _theme_for("bsp")
    theme = theme.copy()
    theme["suptitle"] = "BSP Randomized Search Sensitivity"
    csv_path = os.path.join(results_dir_for(backend),
                            BSP_RANDOM_CSV_TMPL.format(backend=backend))
    out = os.path.join(out_root, f"graphs-{backend}", BSP_SUBDIR, "random")
    return process_csv(
        csv_path, out, theme, f"BSP Randomized Search [{backend}]",
        title_suffix="Randomized Search",
        include_random_variability=True,
    )


def process_compare(problem, out_root):
    spec = PROBLEM_SPECS[problem]
    theme = _theme_for(problem)
    stats_by_backend = {}
    for backend in BACKENDS:
        csv_path = os.path.join(results_dir_for(backend), spec["csv"].format(backend=backend))
        stats = load_stats(csv_path, theme)
        if stats:
            stats_by_backend[backend] = stats
    out = os.path.join(out_root, "graphs-native-prolog", spec["subdir"])
    print(f"\n{'='*60}\n  Confronto {spec['label']} native vs prolog\n  Output: {out}\n{'='*60}")
    return generate_comparison_graphs(
        stats_by_backend, out, theme, spec["label"], LAZY_VARIANTS
    )


def _backend_has_csv(backend):
    for tmpl in (BSP_CSV_TMPL, PUP_CSV_TMPL, BSP_RANDOM_CSV_TMPL):
        path = os.path.join(results_dir_for(backend), tmpl.format(backend=backend))
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            return True
    return False


def main():
    args = parse_args()
    out_root = args.out_root
    exclude_selectors = _split_exclude_selectors(args.exclude)

    graph_trees = [os.path.join(out_root, f"graphs-{b}") for b in BACKENDS]
    graph_trees.append(GRAPHS_COMPARE_DIR if out_root == TEST_ROOT
                       else os.path.join(out_root, "graphs-native-prolog"))

    if args.reset:
        for tree in graph_trees:
            reset_graphs_dir(tree)
        return

    # Valida i selettori --exclude contro il tema della famiglia scelta.
    if exclude_selectors:
        theme = _theme_for(args.type)
        unknown = unmatched_exclude_selectors(exclude_selectors, [theme])
        if unknown:
            print(f"[ERROR] exclude selector non validi per --type {args.type}: "
                  f"{', '.join(unknown)}")
            sys.exit(2)

    backends = [args.backend] if args.backend else list(BACKENDS)
    if any(_backend_has_csv(b) for b in backends):
        ensure_plot_dependencies()

    want = args.type  # None => tutto
    processed_any = False

    for backend in backends:
        if want in (None, "bsp"):
            processed_any |= process_problem(backend, "bsp", exclude_selectors, out_root)
        if want in (None, "pup"):
            processed_any |= process_problem(backend, "pup", exclude_selectors, out_root)
        if want in (None, "bsp_random"):
            processed_any |= process_bsp_random(backend, out_root)

    if want in (None, "compare") and not args.backend:
        for problem in ("bsp", "pup"):
            processed_any |= process_compare(problem, out_root)

    if not processed_any:
        print("\nNessun CSV di risultati trovato.")
        print("Esegui prima i benchmark, ad esempio: benchmarks/0_benchmark.sh")
        sys.exit(1)

    print("\nFatto. Grafici in:")
    for backend in backends:
        print(f"  {os.path.join(out_root, f'graphs-{backend}')}/")
    if want in (None, "compare") and not args.backend:
        print(f"  {os.path.join(out_root, 'graphs-native-prolog')}/")


if __name__ == "__main__":
    main()
