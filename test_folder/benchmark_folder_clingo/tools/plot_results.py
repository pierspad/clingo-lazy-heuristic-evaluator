#!/usr/bin/env python3
"""Grafici dai risultati di benchmark-tool (suite "Lazy Heuristics / Dynamic Aggregates").

Sorgente dati: il file XML prodotto da
    btool eval runscripts/runscript.xml > results.xml
Contiene TUTTE le misure del resultparser custom (resultparsers/clasp.py):
status/timeout/memout, time(wall), mem(picco RSS), solving, grounding,
clingo_total, choices, conflicts, restarts, rules, variables, e — per le
varianti lazy — le statistiche del propagatore (decide_calls,
total_decide_time_ms, total_state_sync_time_ms, ...), ora emesse da ENTRAMBI i
backend: il propagatore C++ stampa "[lazy-native] summary ..." esattamente come
quello prolog stampa "[lazy-prolog] summary ...". Le metriche del propagatore
sono quindi confrontabili fra backend (v. `scope` in Metric); restano
prolog-only le sole fasi legate alla query verso il motore esterno, che nel
backend native non esistono per costruzione.

CONVENZIONE GRAFICA (v. VARIANT_STYLES): colore + marker identificano la
VARIANTE e sono invarianti in tutte le macroaree; il tratto e' la dimensione
libera (tratto canonico della variante negli alberi mono-backend, backend
nell'albero di confronto). Cosi' una variante resta riconoscibile anche nei
grafici da cui e' stata omessa un'altra.

Produce TRE alberi di grafici, una sottocartella per famiglia (1_BSP/2_PUP/3_HRP):

    <out-base>/graphs-native/                varianti MAIN, backend native
    <out-base>/graphs-prolog/                varianti MAIN, backend prolog
    <out-base>/graphs-comparison-native-prolog/   native vs prolog (varianti lazy),
                                             con "verdetto" del migliore per area

Ogni cartella di famiglia ha DUE dashboard: `_dashboard.png` (metriche definite
per tutte le varianti) e `_dashboard_propagator.png` (metriche del propagatore,
che esistono solo per le varianti lazy). Sono domande diverse e hanno un numero
diverso di curve: in un'unica griglia da 26 pannelli non si leggeva niente.

I grafici comparativi principali mostrano SOLO l'encoding di riferimento e le
4 varianti oggetto della tesi (MAIN_VARIANTS): gc_noheur, gc, ga, la, lc.
Le varianti esplorative (la_co, la_aux, ga_weak) NON vi compaiono: vivono in
    <out-base>/graphs-<backend>/exploratory/<studio>/<famiglia>/
con tre studi dedicati (v. EXPLORATORY_STUDIES):
    la_co_grounding   effetto della linearizzazione del vincolo sul grounding
                      (drastica riduzione delle regole groundate, spec. BSP)
    la_aux_vs_gs      la_aux forza un comportamento ground-and-solve-like:
                      atteso ~gc; confronto con gc_noheur/gc/ga/la
    ga_vs_ga_weak     ga (negazione rimossa + unrolling aggregati con somma e
                      vincolo <) vs ga_weak (solo negazione-as-alpha,
                      aggregato invariato)

Opzionale: --ground-counts output/ground_counts.csv abilita i grafici di
conteggio del grounding (ground_heuristics, __heuristic facts, combined,
ground_lines) e lo scatter grounding-time vs heuristic-size, che NON vivono in
results.xml (sono prodotti dal passo disaccoppiato tools/ground_counts.py).

Uso:
    python3 tools/plot_results.py --out-base ..            # full -> test_folder/
    python3 tools/plot_results.py --out-base . --machine local
    python3 tools/plot_results.py --results results.xml --out-base .. \
            --ground-counts output/ground_counts.csv
"""
from __future__ import annotations

import argparse
import math
import re
import shutil
import textwrap
import xml.etree.ElementTree as ET
from collections.abc import Callable
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.ticker import FuncFormatter, MaxNLocator  # noqa: E402
import pandas as pd  # noqa: E402

# ---------------------------------------------------------------------------
# Mappa istanza -> (famiglia, taglia). I nomi seguono lo schema del runscript.
# ---------------------------------------------------------------------------
INSTANCE_RE = re.compile(r"^(?P<fam>bsp|double|house)-(?P<size>\d+)", re.IGNORECASE)
FAMILY = {"bsp": "BSP", "double": "PUP", "house": "HRP"}
FAM_SUBDIR = {"BSP": "1_BSP", "PUP": "2_PUP", "HRP": "3_HRP"}
BACKENDS = ("native", "prolog")

BACKEND_DISPLAY = {"native": "C++", "prolog": "Prolog"}
BACKEND_LABEL = {"native": "C++ backend", "prolog": "Prolog backend"}


def backend_label(backend: str) -> str:
    return BACKEND_LABEL.get(backend, f"{backend} backend")


def backend_short(backend: str) -> str:
    return BACKEND_DISPLAY.get(backend, backend)


# Il solver Alpha entra in results.xml come un terzo `system` e quindi come un
# terzo "backend" dopo la normalizzazione del nome. NON viene aggiunto a
# BACKENDS di proposito: BACKENDS enumera i due backend DEL PROPAGATORE di
# questa tesi, che condividono varianti, metriche e alberi di grafici. Alpha
# non condivide nulla di tutto cio' — e' un sistema esterno con un solo
# encoding e contatori suoi — e finirebbe in ogni albero mono-backend come una
# cartella quasi vuota, e nel confronto native-vs-prolog come un terzo
# incomodo. Ha il suo albero dedicato: v. render_alpha_tree().
ALPHA_BACKEND = "alpha-qh"

# ---------------------------------------------------------------------------
# IDENTITA' VISIVA DELLE VARIANTI — convenzione unica per TUTTE le macroaree.
#
# Il problema: la stessa variante compare in piu' macroaree, e nell'albero di
# confronto compare DUE volte (una per backend). Se il tratto identificasse la
# variante, nel confronto servirebbe un secondo tratto per il backend e la
# variante cambierebbe aspetto da un grafico all'altro. Peggio: quando una
# variante viene omessa da un grafico (esclusioni, metriche non definite,
# timeout precoci) i colori "scalerebbero" e la lettura incrociata salterebbe.
#
# La soluzione e' separare due canali ortogonali:
#
#   IDENTITA' DELLA VARIANTE = colore + marker.
#       Fissi, unici (nessun colore e nessun marker condiviso da due varianti)
#       e MAI riusati per altro, in ogni albero e in ogni macroarea. Sono
#       assegnati per NOME della variante, non per posizione: se una variante
#       manca dal grafico le altre non cambiano aspetto.
#
#   DIMENSIONE LIBERA = tratto (linestyle).
#       Il suo significato dipende dalla macroarea ed e' sempre dichiarato in
#       legenda:
#         - alberi mono-backend (graphs-native/, graphs-prolog/, exploratory/):
#           tratto = tratto canonico della variante (ridondante col colore,
#           serve alla leggibilita' in stampa b/n);
#         - albero di confronto (graphs-comparison-native-prolog/):
#           tratto = BACKEND (native pieno/continuo, prolog vuoto/tratteggiato),
#           mentre colore e marker continuano a dire QUALE variante e'.
#
# La prima lettera del nome = approccio (g* ground-and-solve, l* lazy);
# l'ultima = semantica (*c clingo-like, *a alpha-like). Colori e marker
# rispettano la parentela: le varianti derivate da X hanno il colore di X in
# tonalita' vicina e un marker della stessa famiglia geometrica.
# ---------------------------------------------------------------------------
class VariantStyle:
    """Aspetto di UNA variante. `color`/`marker` sono l'identita' (invarianti);
    `dash` e' il tratto canonico, usato solo dove il tratto e' libero."""

    __slots__ = ("label", "color", "marker", "dash")

    def __init__(self, label: str, color: str, marker: str, dash):
        self.label = label
        self.color = color
        self.marker = marker
        self.dash = dash


VARIANT_STYLES: dict[str, VariantStyle] = {
    # riferimento: nessuna euristica
    "gc_noheur": VariantStyle("G&S Clingo (no heur)", "#34495E", "X", (0, (1, 1.8))),
    # ground-and-solve
    "gc":        VariantStyle("G&S Clingo",           "#E74C3C", "o", (0, (6, 2))),
    "ga":        VariantStyle("G&S Alpha",            "#F39C12", "^", (0, (3, 1.4))),
    "ga_weak":   VariantStyle("G&S Alpha (weak)",     "#B9770E", "v", (0, (3, 1.4, 1, 1.4))),
    # lazy
    "la":        VariantStyle("Lazy Alpha",           "#27AE60", "s", "solid"),
    "lc":        VariantStyle("Lazy Clingo",          "#8E44AD", "D", (0, (7, 1.6, 1, 1.6))),
    "la_aux":    VariantStyle("Lazy Alpha + Aux",     "#16A085", "P", (0, (5, 1.2, 1, 1.2, 1, 1.2))),
    "la_co":     VariantStyle("Lazy Alpha + ConstrOpt", "#2E86C1", "d", (0, (4, 1.2, 4, 1.2, 1, 1.2))),
    # --- sistema esterno: Alpha (lazy grounding nativo) -------------------
    # Colori volutamente FUORI dalle famiglie cromatiche di sopra: nei grafici
    # di confronto si deve vedere a colpo d'occhio quali curve sono clingo e
    # quale e' l'altro solver.
    "alpha":        VariantStyle("Alpha Qh (dyn. aggr.)", "#D81B60", "*", "solid"),
    "alpha_noheur": VariantStyle("Alpha (no heur)",       "#795548", "x", (0, (1, 1.8))),
    # HRP-only: euristiche domain-specific senza -uqh (v. il setting
    # alpha_dom nel runscript). Colore imparentato con "alpha" perche' e' lo
    # stesso sistema con lo stesso encoding, marker diverso perche' e' un
    # altro modo di valutare l'euristica.
    "alpha_dom":    VariantStyle("Alpha (domspec nativo)", "#F06292", "p", (0, (5, 1.5))),
}

# Fallback per una variante non ancora censita (non deve succedere: meglio
# accorgersene da un grigio anonimo che da un colore rubato a un'altra).
_FALLBACK_STYLE = VariantStyle("?", "#7F8C8D", "8", (0, (2, 2)))


def style_of(variant: str) -> VariantStyle:
    return VARIANT_STYLES.get(variant, _FALLBACK_STYLE)


def label_of(variant: str) -> str:
    return VARIANT_STYLES[variant].label if variant in VARIANT_STYLES else variant


def variant_kwargs(variant: str, *, dash=None, **overrides) -> dict:
    """kwargs di ax.plot per una variante. Colore e marker sono sempre quelli
    dell'identita'; `dash=None` usa il tratto canonico, altrimenti il chiamante
    impone il proprio (es. il backend nell'albero di confronto)."""
    st = style_of(variant)
    kwargs = {
        "color": st.color,
        "marker": st.marker,
        "linestyle": st.dash if dash is None else dash,
        "linewidth": 1.8,
        "markersize": 4.5,
        "markeredgecolor": "white",
        "markeredgewidth": 0.6,
        "label": st.label,
    }
    kwargs.update(overrides)
    return kwargs


VARIANT_ORDER = ["gc_noheur", "gc", "ga", "ga_weak", "la", "lc", "la_aux", "la_co"]
LAZY_VARIANTS = ["la", "lc", "la_aux", "la_co"]

# Varianti del confronto principale della tesi: 1 riferimento + 4 varianti.
# Tutto il resto (la_co, la_aux, ga_weak) e' esplorativo e compare solo
# nell'albero exploratory/.
MAIN_VARIANTS = ["gc_noheur", "gc", "ga", "la", "lc"]
MAIN_LAZY_VARIANTS = ["la", "lc"]

# ---------------------------------------------------------------------------
# Studi esplorativi: ogni studio disegna i singoli PNG delle metriche indicate
# + un _dashboard.png, ristretti alle sole varianti dello studio.
#   ground=True aggiunge anche i grafici di conteggio grounding (richiede
#   --ground-counts), che per la_co sono il cuore dell'analisi.
# ---------------------------------------------------------------------------
EXPLORATORY_STUDIES = [
    {
        "slug": "la_co_grounding",
        "title": "la_co: constraint linearisation and its impact on grounding",
        "variants": ["gc", "la", "lc", "la_co"],
        "metrics": ["grounding", "solving", "clingo_total", "mem", "rules", "constraints"],
        "ground": True,
    },
    {
        "slug": "la_aux_vs_gs",
        "title": "la_aux: forced ground-and-solve behaviour (expected ~gc)",
        "variants": ["gc_noheur", "gc", "ga", "la", "la_aux"],
        "metrics": ["grounding", "solving", "clingo_total", "mem",
                    "choices", "conflicts", "decide_calls"],
        "ground": False,
    },
    {
        "slug": "ga_vs_ga_weak",
        "title": "ga vs ga_weak: aggregate unrolling vs alpha-negation alone",
        "variants": ["gc_noheur", "gc", "ga", "ga_weak", "la", "lc"],
        "metrics": ["grounding", "solving", "clingo_total", "mem",
                    "choices", "conflicts", "rules", "constraints"],
        "ground": False,
    },
]

XLABEL = {"BSP": "Problem size (N)", "PUP": "Instance size (N)", "HRP": "Instance size (persons N)"}


# ---------------------------------------------------------------------------
# Metriche da results.xml. Tutte "lower is better".
#
# `scope` dice CHI puo' avere quel dato, ed e' l'unico posto in cui la
# distinzione fra backend e' codificata:
#   "all"        -> ogni variante, ogni backend (tempi, memoria, conteggi clasp)
#   "propagator" -> solo varianti lazy (l*), ma su ENTRAMBI i backend: sono le
#                   statistiche emesse dalla riga "[lazy-<backend>] summary"
#                   (decide_calls, tempi di decide/sync/scan, candidati). Da
#                   quando anche il propagatore C++ e' strumentato queste
#                   metriche sono CONFRONTABILI fra native e prolog e quindi
#                   hanno senso nell'albero di confronto.
#   "prolog"     -> solo varianti lazy sul backend prolog: misurano la query
#                   verso il motore esterno, che nel backend native non esiste
#                   per costruzione (non e' un dato mancante, e' una fase che
#                   non c'e'). Restano fuori dal confronto native-vs-prolog.
#   "native"     -> solo varianti lazy sul backend native: contatori interni
#                   del propagatore in-memory senza analogo lato prolog.
# ---------------------------------------------------------------------------
SCOPE_ALL = "all"
SCOPE_PROPAGATOR = "propagator"
SCOPE_PROLOG = "prolog"
SCOPE_NATIVE = "native"

# Nota in calce ai grafici delle metriche a scope ristretto: senza, un grafico
# con una sola curva sembra un grafico rotto invece che una misura che per
# l'altro backend non e' definita.
SCOPE_NOTES = {
    SCOPE_PROPAGATOR: "propagator metric: defined only for the lazy variants (l*)",
    SCOPE_PROLOG: "Prolog-backend metric: the C++ backend has no query phase "
                  "towards an external engine",
    SCOPE_NATIVE: "C++ backend metric (in-memory C++ propagator)",
}


class Metric:
    def __init__(self, key, title, ylabel, *, scope=SCOPE_ALL, fmt="auto", log=False):
        self.key = key
        self.title = title
        self.ylabel = ylabel
        self.scope = scope
        self.fmt = fmt
        # asse y logaritmico: da usare SOLO dove le curve stanno su ordini di
        # grandezza diversi e la piu' alta schiaccerebbe le altre sullo zero
        # (v. le consultazioni nell'albero Alpha-vs-backend-prolog). Su una
        # scala log il confronto e' fra RAPPORTI: va dichiarato in figura.
        self.log = log

    @property
    def lazy_only(self) -> bool:
        """Vera per tutte le metriche del propagatore, qualunque il backend."""
        return self.scope != SCOPE_ALL

    def backends(self) -> tuple[str, ...]:
        if self.scope == SCOPE_PROLOG:
            return ("prolog",)
        if self.scope == SCOPE_NATIVE:
            return ("native",)
        return BACKENDS

    def applies_to(self, backend: str) -> bool:
        return backend in self.backends()


METRICS = [
    Metric("solving", "Solving Time", "Time (s)"),
    Metric("grounding", "Grounding Time", "Time (s)"),
    Metric("clingo_total", "Total Time (clingo)", "Time (s)"),
    Metric("mem", "Peak RSS Memory", "Memory (GB)", fmt="gb"),
    Metric("choices", "Choices", "Choices", fmt="compact"),
    Metric("conflicts", "Conflicts", "Conflicts", fmt="compact"),
    Metric("restarts", "Restarts", "Restarts", fmt="compact"),
    Metric("rules", "Solver Rules", "Rules", fmt="compact"),
    Metric("variables", "Solver Variables", "Variables", fmt="compact"),
    Metric("solving_ms_per_choice", "Solving Cost per Choice", "ms / choice"),
    # --- propagatore, confrontabili fra backend ---
    Metric("decide_calls", "Propagator Decide Calls", "decide_calls",
           scope=SCOPE_PROPAGATOR, fmt="compact"),
    Metric("ms_per_decide", "Propagator Cost per Decision", "ms / decide",
           scope=SCOPE_PROPAGATOR),
    Metric("total_decide_time_ms", "Total Decide Time", "Time (ms)",
           scope=SCOPE_PROPAGATOR, fmt="compact"),
    Metric("total_propagator_time_ms", "Total Propagator Overhead (decide + sync)", "Time (ms)",
           scope=SCOPE_PROPAGATOR, fmt="compact"),
    # --- propagatore, specifiche del backend prolog ---
    Metric("total_prolog_query_time_ms", "Total Prolog Query Time", "Time (ms)",
           scope=SCOPE_PROLOG, fmt="compact"),
    Metric("prolog_ms_per_decide", "Prolog Query Cost per Decision", "ms / decide",
           scope=SCOPE_PROLOG),
]

# Metriche EXTRA, anch'esse gia' in results.xml ma non nel set "core". Vengono
# disegnate come singoli PNG e accodate IN FONDO al dashboard generale.
#   - atoms/constraints: dimensione strutturale del programma (come rules/variables)
#   - time: wall-clock di runlim (end-to-end del processo, include overhead/IO),
#     da leggere accanto a clingo_total (tempo interno a clingo)
#   - scomposizione del costo del propagatore lazy: decide = sync + query +
#     scan + lookup + selection; + quanti candidati vede per decisione.
EXTRA_METRICS = [
    Metric("atoms", "Solver Atoms", "atoms", fmt="compact"),
    Metric("constraints", "Solver Constraints", "constraints", fmt="compact"),
    Metric("time", "Wall Time (runlim)", "Time (s)"),
    # scomposizione del costo del propagatore: comune ai due backend
    Metric("total_state_sync_time_ms", "State Sync Time", "Time (ms)",
           scope=SCOPE_PROPAGATOR, fmt="compact"),
    Metric("total_candidate_scan_time_ms", "Candidate Scan Time", "Time (ms)",
           scope=SCOPE_PROPAGATOR, fmt="compact"),
    Metric("total_candidates_seen", "Total Candidates Seen", "candidates",
           scope=SCOPE_PROPAGATOR, fmt="compact"),
    Metric("avg_candidates_per_decide", "Avg Candidates per Decide", "candidates / decide",
           scope=SCOPE_PROPAGATOR),
    Metric("max_candidates_seen", "Max Candidates in a Decide", "candidates",
           scope=SCOPE_PROPAGATOR, fmt="compact"),
    # fasi che esistono solo nel backend prolog (query verso SWI)
    Metric("total_literal_lookup_time_ms", "Literal Lookup Time", "Time (ms)",
           scope=SCOPE_PROLOG, fmt="compact"),
    Metric("total_candidate_selection_time_ms", "Candidate Selection Time", "Time (ms)",
           scope=SCOPE_PROLOG, fmt="compact"),
    # contatori interni del solo propagatore C++
    Metric("decide_hits", "Decide Calls with a Decision", "decide_hits",
           scope=SCOPE_NATIVE, fmt="compact"),
    Metric("decide_hit_ratio", "Decide Hit Ratio", "decisioni / chiamate",
           scope=SCOPE_NATIVE),
    Metric("propagate_calls", "Propagate Calls", "propagate_calls",
           scope=SCOPE_NATIVE, fmt="compact"),
    Metric("undo_calls", "Undo Calls", "undo_calls",
           scope=SCOPE_NATIVE, fmt="compact"),
]
METRICS = METRICS + EXTRA_METRICS
METRIC_BY_KEY = {m.key: m for m in METRICS}

# Aree del confronto native-vs-prolog ("le varie aree").
# REGOLA: qui entrano SOLO metriche misurabili su entrambi i backend (scope
# "all" o "propagator"). Una metrica che per costruzione esiste su un backend
# solo (prolog_ms_per_decide, total_prolog_query_time_ms, i contatori native)
# in un grafico "native vs prolog" produrrebbe un confronto con se stessa: vive
# negli alberi mono-backend, dove ha senso. Il controllo e' anche automatico,
# v. _comparison_areas().
COMPARISON_AREAS = ["solving", "grounding", "clingo_total", "mem",
                    "decide_calls", "ms_per_decide", "total_decide_time_ms",
                    "total_propagator_time_ms", "total_state_sync_time_ms"]

# Dashboard per-backend: una "immagine generale" con tutto. I pannelli CORE
# stanno in alto; gli EXTRA vengono ACCODATI sotto (righe finali), nell'ordine.
# Le due liste vengono poi RIPARTITE su due figure in base allo scope della
# metrica (v. _render_dashboard): _dashboard.png con le metriche di tutte le
# varianti, _dashboard_propagator.png con quelle del propagatore (solo lazy).
DASHBOARD_CORE =["grounding", "solving", "clingo_total", "mem",
                  "choices", "conflicts", "restarts", "solving_ms_per_choice"]
DASHBOARD_EXTRA = ["rules", "variables", "atoms", "constraints", "time",
                   "decide_calls", "ms_per_decide", "total_decide_time_ms",
                   "total_propagator_time_ms", "total_state_sync_time_ms",
                   "total_candidate_scan_time_ms", "total_candidates_seen",
                   "avg_candidates_per_decide", "max_candidates_seen",
                   "total_prolog_query_time_ms", "prolog_ms_per_decide",
                   "total_literal_lookup_time_ms", "total_candidate_selection_time_ms",
                   "decide_hits", "decide_hit_ratio", "propagate_calls", "undo_calls"]

# Conteggi di grounding (solo con --ground-counts).
GROUND_METRICS = [
    Metric("ground_heuristics", "Ground #heuristic Directives", "#heuristic", fmt="compact"),
    Metric("ground_lazy_heuristic_facts", "Ground __heuristic Facts", "__heuristic facts", fmt="compact"),
    Metric("combined_heuristics", "Heuristic Grounding (combined)", "ground heuristic entries", fmt="compact"),
    Metric("ground_lines", "Ground Program Lines", "lines (--text)", fmt="compact"),
]


# ===========================================================================
# Parsing results.xml -> tidy -> aggregato per (backend, setting, family, size)
# ===========================================================================
def load_tidy(results_xml: Path) -> pd.DataFrame:
    root = ET.parse(results_xml).getroot()

    bench: dict[str, dict[str, dict[str, str]]] = {}
    for b in root.findall("benchmark"):
        cmap: dict[str, dict[str, str]] = {}
        for cls in b.findall("class"):
            cmap[cls.get("id")] = {inst.get("id"): inst.get("name") for inst in cls.findall("instance")}
        bench[b.get("name")] = cmap

    rows = []
    for project in root.findall("project"):
        for rs in project.findall("runspec"):
            machine, system, setting, bname = (
                rs.get("machine"), rs.get("system"), rs.get("setting"), rs.get("benchmark"))
            cmap = bench.get(bname, {})
            for cls in rs.findall("class"):
                imap = cmap.get(cls.get("id"), {})
                for inst in cls.findall("instance"):
                    iname = imap.get(inst.get("id"), inst.get("id"))
                    for run in inst.findall("run"):
                        for m in run.findall("measure"):
                            rows.append({
                                "instance": iname, "measure": m.get("name"),
                                "system": system, "setting": setting,
                                "machine": machine, "run": run.get("number", "0"),
                                "value": m.get("val"),
                            })
    tidy = pd.DataFrame.from_records(rows)
    if tidy.empty:
        return tidy

    fam, size = [], []
    for name in tidy["instance"]:
        mo = INSTANCE_RE.match(str(name))
        fam.append(FAMILY[mo.group("fam").lower()] if mo else "?")
        size.append(int(mo.group("size")) if mo else -1)
    tidy["family"] = fam
    tidy["size"] = size
    tidy["backend"] = (tidy["system"].str.replace("clingo-", "", regex=False)
                                     .str.replace("-1.0", "", regex=False))
    return tidy


def aggregate(tidy: pd.DataFrame, machine: str) -> pd.DataFrame:
    """Una riga per (backend, setting, family, size): mediana sulle istanze
    risolte. Le derivate (per-choice, per-decide) sono calcolate per-run prima
    di aggregare. I run non risolti (timeout/error/memout) sono esclusi."""
    sub = tidy[tidy["machine"] == machine]
    if sub.empty:
        return pd.DataFrame()

    wide = sub.pivot_table(
        index=["backend", "setting", "family", "size", "instance", "run"],
        columns="measure", values="value", aggfunc="first",
    ).reset_index()

    for col in wide.columns:
        if col not in ("backend", "setting", "family", "instance", "run"):
            wide[col] = pd.to_numeric(wide[col], errors="coerce")

    # filtro: tieni solo i run risolti (i flag, se assenti, valgono 0).
    for flag in ("timeout", "error", "memout"):
        if flag not in wide.columns:
            wide[flag] = 0.0
    solved = ((wide["timeout"].fillna(1) == 0)
              & (wide["error"].fillna(1) == 0)
              & (wide["memout"].fillna(1) == 0))
    wide = wide[solved].copy()
    if wide.empty:
        return pd.DataFrame()

    # derivate per-run. Sono ricalcolate qui (non solo nel resultparser) cosi'
    # che valgano anche sui results.xml gia' prodotti prima che il parser le
    # emettesse: nessun bisogno di rieseguire l'eval per ottenerle.
    if {"solving", "choices"}.issubset(wide.columns):
        wide["solving_ms_per_choice"] = 1000.0 * wide["solving"] / wide["choices"].where(wide["choices"] > 0)

    decide = wide["decide_calls"].where(wide["decide_calls"] > 0) if "decide_calls" in wide.columns else None
    # costo medio di UNA decisione del propagatore: la metrica confrontabile
    # fra i due backend (in-memory vs query esterna).
    if decide is not None and "total_decide_time_ms" in wide.columns:
        wide["ms_per_decide"] = wide["total_decide_time_ms"] / decide
    # quota della sola query prolog dentro la decisione (backend prolog).
    if decide is not None and "total_prolog_query_time_ms" in wide.columns:
        wide["prolog_ms_per_decide"] = wide["total_prolog_query_time_ms"] / decide
    # overhead totale dell'euristica = decidere + tenere sincronizzato lo stato
    # (in propagate/undo). E' il "prezzo" complessivo del propagatore.
    if {"total_decide_time_ms", "total_state_sync_time_ms"}.issubset(wide.columns):
        parts = wide[["total_decide_time_ms", "total_state_sync_time_ms"]]
        # somma solo dove ALMENO una delle due componenti e' stata misurata:
        # con un fillna(0) cieco un backend privo di statistiche risulterebbe
        # con overhead 0 e vincerebbe ogni confronto senza aver misurato nulla.
        wide["total_propagator_time_ms"] = parts.sum(axis=1, min_count=1)
    # frazione di chiamate a decide() in cui il propagatore ha davvero deciso
    # (backend native): il resto sono chiamate a vuoto, costo puro.
    if decide is not None and "decide_hits" in wide.columns:
        wide["decide_hit_ratio"] = wide["decide_hits"] / decide

    value_cols = [c for c in wide.columns
                  if c not in ("backend", "setting", "family", "size", "instance", "run")]
    agg = (wide.groupby(["backend", "setting", "family", "size"])[value_cols]
                .median().reset_index())
    return agg


def attempted_settings(tidy: pd.DataFrame, machine: str) -> dict[tuple[str, str], set[str]]:
    """{(backend, family): varianti LANCIATE}, timeout inclusi. `aggregate`
    tiene solo i run risolti: una variante che fallisce ovunque sparisce dai
    dati e diventa indistinguibile da una mai eseguita. Serve ai grafici che
    devono dire "provata e mai riuscita" invece di tacere (v. frontiera)."""
    sub = tidy[tidy["machine"] == machine]
    return {k: set(v) for k, v in
            sub.groupby(["backend", "family"])["setting"].unique().to_dict().items()}


# ===========================================================================
# Formattazione assi
# ===========================================================================
def _fmt_compact(v, _p=None):
    av = abs(v)
    for suf, sc in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if av >= sc:
            s = v / sc
            return (f"{s:.0f}{suf}" if abs(s) >= 100 or float(s).is_integer()
                    else f"{s:.1f}{suf}".rstrip("0").rstrip("."))
    return "0" if v == 0 else (f"{v:.0f}" if av >= 1 else f"{v:g}")


def _fmt_gb_from_mb(v, _p=None):
    g = v / 1024.0
    if v == 0:
        return "0"
    return f"{g:.0f}" if abs(g) >= 100 or g.is_integer() else f"{g:.2f}".rstrip("0").rstrip(".")


class _GBLocator(MaxNLocator):
    """Tick su valori "tondi" in GB per un asse i cui DATI sono in MB.

    MaxNLocator sceglie multipli tondi dell'unita' dei dati: sui MB da'
    5000/10000/15000, che l'etichettatore in GB rende come 4.88/9.77/14.65.
    Qui i tick si scelgono in GB e si riconvertono in MB solo alla fine."""

    def tick_values(self, vmin, vmax):
        return [t * 1024.0 for t in super().tick_values(vmin / 1024.0, vmax / 1024.0)]


def _apply_fmt(ax, metric: Metric):
    if metric.log:
        # la scala log rimpiazza il LOCATOR (MaxNLocator qui darebbe tick
        # equispaziati in valore su un asse equispaziato in decadi) ma non il
        # formatter: un asse in MB resta da etichettare in GB anche in log.
        ax.set_yscale("log")
        ax.yaxis.set_major_formatter(FuncFormatter(
            _fmt_gb_from_mb if metric.fmt == "gb" else _fmt_compact))
        ax.yaxis.offsetText.set_visible(False)
        return
    if metric.fmt == "gb":
        ax.yaxis.set_major_locator(_GBLocator(nbins=6))
        ax.yaxis.set_major_formatter(FuncFormatter(_fmt_gb_from_mb))
    elif metric.fmt == "compact":
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6))
        ax.yaxis.set_major_formatter(FuncFormatter(_fmt_compact))
    ax.yaxis.offsetText.set_visible(False)


def _wrap(text: str, width: int) -> str:
    """Titolo a capo su piu' righe: un titolo piu' largo del pannello sconfina
    sulla cella accanto (in dashboard) o viene tagliato dal crop di savefig.
    Gli a capo gia' presenti nel testo sono rispettati."""
    return "\n".join("\n".join(textwrap.wrap(line, width)) or line
                     for line in text.split("\n"))


def _figure_note(fig, text: str, *, width: int = 140, y: float = 0.015,
                 reserve: bool = True) -> None:
    """Nota in calce alla FIGURA, non all'axes.

    Prima era un ax.text a y=-0.20 in coordinate axes: (a) nei grafici singoli
    finiva SOPRA l'xlabel, (b) nelle dashboard tight_layout la conta come parte
    dell'axes e, essendo larga il triplo del pannello, restringeva il grafico
    fino a renderlo illeggibile (era il caso di HRP/prolog). Un testo di FIGURA
    non appartiene a nessun axes: tight_layout non lo vede, e il crop di
    savefig(bbox_inches="tight") lo tiene."""
    if reserve:
        fig.subplots_adjust(bottom=max(0.17, fig.subplotpars.bottom))
    fig.text(0.01, y, textwrap.fill(text, width), fontsize=6.5,
             color="#7F8C8D", ha="left", va="bottom", style="italic")


# ===========================================================================
# Disegno di una singola metrica (una curva per variante)
# ===========================================================================
def _variants_present(agg_fb: pd.DataFrame, allowed: list[str] | None = None) -> list[str]:
    """Varianti presenti nei dati, nell'ordine canonico. Di default filtra
    alle sole MAIN_VARIANTS: le esplorative si ottengono passando `allowed`."""
    present = set(agg_fb["setting"].unique())
    order = allowed if allowed is not None else MAIN_VARIANTS
    return [v for v in order if v in present]


def _scope_note(ax, metric: Metric) -> None:
    """Nota in calce per le metriche a scope ristretto: dichiara PERCHE' certe
    varianti/backend non compaiono, invece di lasciare il grafico monco."""
    note = SCOPE_NOTES.get(metric.scope)
    if note:
        _figure_note(ax.figure, note)


def _plot_metric_axis(ax, agg_fb: pd.DataFrame, metric: Metric, family: str, *, variants=None,
                      title: str | None = None, title_width: int = 80,
                      legend: bool = True, note: bool = True) -> bool:
    """Disegna UNA metrica. `title` sostituisce il titolo di default (il
    chiamante che ha un titolo piu' informativo lo passa qui invece di
    aggiungere una suptitle sopra: due titoli sovrapposti sullo stesso grafico
    dicevano la stessa cosa due volte). `legend=False`/`note=False` servono
    alle dashboard, che hanno una legenda condivisa e le note a pie' di
    figura."""
    heading = _wrap(metric.title if title is None else title, title_width)
    if metric.key not in agg_fb.columns:
        ax.text(0.5, 0.5, "metric not available", transform=ax.transAxes, ha="center", va="center", color="#AAA")
        ax.set_title(heading, fontsize=11, fontweight="bold")
        return False
    variants = variants if variants is not None else _variants_present(agg_fb)
    drew = False
    for v in variants:
        d = agg_fb[agg_fb["setting"] == v].dropna(subset=[metric.key]).sort_values("size")
        if d.empty:
            continue
        # Tratto libero => tratto canonico della variante (v. VARIANT_STYLES).
        ax.plot(d["size"], d[metric.key], **variant_kwargs(v))
        drew = True
    ax.set_title(heading, fontsize=11, fontweight="bold")
    ax.set_xlabel(XLABEL.get(family, "size (N)"), fontsize=9)
    ax.set_ylabel(metric.ylabel, fontsize=9)
    ax.grid(True, alpha=0.3, linestyle="--")
    _apply_fmt(ax, metric)
    if drew:
        if legend:
            # ncol=1: a 2 colonne la legenda e' piu' larga dell'axes appena le
            # etichette sono lunghe ("G&S Clingo (no heur)") e finisce sui dati.
            ax.legend(fontsize=7, ncol=1, framealpha=0.85)
        if note:
            _scope_note(ax, metric)
    return drew


# ---------------------------------------------------------------------------
# Griglia di pannelli (dashboard). UNA legenda condivisa in testa, note di
# scope a pie' di figura: dentro una cella da 4.6" una legenda per pannello e'
# piu' larga dell'axes, e tight_layout — che la conta come parte dell'axes —
# comprimeva il grafico fino a lasciarne un francobollo (HRP/prolog).
# ---------------------------------------------------------------------------
def _dashboard_grid(agg_fb: pd.DataFrame, family: str, metrics: list[Metric], *,
                    variants: list[str], lazy_variants: list[str],
                    suptitle: str, path: Path, ncol: int = 4,
                    panel: tuple[float, float] = (4.6, 3.4),
                    row_break_after: int = 0,
                    extra_notes: list[str] | None = None) -> int:
    if not metrics:
        return 0
    panels: list[Metric | None] = list(metrics)
    if 0 < row_break_after < len(metrics):
        pad = (-row_break_after) % ncol
        panels = metrics[:row_break_after] + [None] * pad + metrics[row_break_after:]
    nrow = math.ceil(len(panels) / ncol)
    fig_h = panel[1] * nrow
    fig, axes = plt.subplots(nrow, ncol, figsize=(panel[0] * ncol, fig_h), squeeze=False)
    flat = axes.flatten()

    handles: dict[str, object] = {}
    notes: list[str] = list(extra_notes or [])
    for ax, metric in zip(flat, panels):
        if metric is None:
            ax.axis("off")
            continue
        vs = lazy_variants if metric.lazy_only else variants
        drew = _plot_metric_axis(ax, agg_fb, metric, family, variants=vs,
                                 title_width=34, legend=False, note=False)
        if not drew:
            continue
        for h, lab in zip(*ax.get_legend_handles_labels()):
            handles.setdefault(lab, h)
        n = SCOPE_NOTES.get(metric.scope)
        if n and n not in notes:
            notes.append(n)
    for ax in flat[len(panels):]:
        ax.axis("off")

    # margini in POLLICI convertiti in frazione: cosi' la banda di titolo e
    # legenda resta della stessa altezza qualunque sia il numero di righe.
    top_pad = 0.85 / fig_h
    bot_pad = (0.20 + 0.16 * len(notes)) / fig_h if notes else 0.06 / fig_h
    fig.tight_layout(rect=(0, bot_pad, 1, 1 - top_pad))
    fig.suptitle(suptitle, fontsize=15, fontweight="bold", y=1 - 0.22 / fig_h)
    if handles:
        fig.legend(list(handles.values()), list(handles), loc="upper center",
                   bbox_to_anchor=(0.5, 1 - 0.44 / fig_h), ncol=min(len(handles), 7),
                   fontsize=9, frameon=True, framealpha=0.9)
    if notes:
        fig.text(0.008, 0.06 / fig_h, "\n".join(textwrap.fill(n, 220) for n in notes),
                 fontsize=8, color="#7F8C8D", ha="left", va="bottom", style="italic")
    _save(fig, path)
    return 1


def _save(fig, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=140, bbox_inches="tight")
    plt.close(fig)


# ===========================================================================
# Alberi per-backend (graphs-native / graphs-prolog)
# ===========================================================================
# Esclusione varianti: per ogni entry qui sotto, in AGGIUNTA all'albero
# normale (tutte le MAIN_VARIANTS), viene generato un secondo albero completo
# (stessi metrics + dashboard + ratio + ground) con la/le variante/i indicata/e
# tolta/e dai grafici — utile quando una variante ha una scala/andamento cosi'
# diverso dalle altre da schiacciarle nel plot (es. "ga": G&S Alpha, "lc":
# Lazy Clingo, entrambe soggette a timeout precoci che comprimono le altre
# curve). "exclude" accetta una stringa (una variante) o una lista (piu'
# varianti tolte assieme dallo stesso albero).
# Cartella gemella: "<FAM_SUBDIR>-<slug>" (es. "1_BSP-no_ga"), stesso livello
# di "1_BSP" dentro graphs-native/ e graphs-prolog/.
# Estendibile in futuro: per aggiungere una nuova combinazione basta
# accodare un'altra entry a questa lista — non serve toccare nient'altro:
# il resto della pipeline (render_backend_tree, _summary_sources, build_jobs)
# legge gia' `slug`/`exclude`/`label` in modo generico e (ri)scrive la
# cartella gemella "<FAM_SUBDIR>-<slug>" da zero ad ogni run (v. cleanup in
# render_backend_tree). Se il run successivo cambia la definizione di uno
# slug esistente (es. si aggiunge una variante all'exclude), la cartella
# viene interamente rigenerata: nessun PNG "vecchio" rimane in giro.
#   "exclude": una variante singola (stringa) o piu' varianti (lista) da
#              togliere dalle MAIN_VARIANTS per QUESTO albero gemello.
# Esempio per aggiungerne una nuova ("solo senza gc"):
#   {"slug": "no_gc", "exclude": "gc", "label": "senza G&S Clingo (gc)"},
VARIANT_EXCLUSIONS = [
    {"slug": "no_ga", "exclude": "ga", "label": "senza G&S Alpha (ga)"},
    {"slug": "no_lc", "exclude": "lc", "label": "senza Lazy Clingo (lc)"},
    {"slug": "no_ga_lc", "exclude": ["ga", "lc"],
     "label": "senza G&S Alpha (ga) e Lazy Clingo (lc)"},
]


def _exclude_set(excl: dict) -> set[str]:
    v = excl["exclude"]
    return {v} if isinstance(v, str) else set(v)


# ===========================================================================
# Zoom a posteriori sulla scala (size/N): quando UNA variante isolata scala
# molto oltre le altre (es. su BSP tutte si fermano a N=100 tranne "la" che
# arriva a 200), l'asse x/y del grafico si auto-scala sul suo punto piu'
# estremo e le differenze fra le altre varianti (che si fermano molto prima)
# restano schiacciate a sinistra. Ogni entry qui sotto genera un ALBERO
# GEMELLO aggiuntivo (stessi metrics/dashboard/ratio/ground della family, non
# serve rieseguire i benchmark: opera solo in fase di plot sugli STESSI dati
# aggregati) con i punti a size > max_size scartati PRIMA di disegnare, cosi'
# l'asse si auto-scala sul sottoinsieme leggibile.
# Cartella gemella: "<FAM_SUBDIR>-<slug>" (stesso schema di VARIANT_EXCLUSIONS,
# namespace condiviso: usa slug distinti dalle esclusioni). Se per una data
# family il cap non taglia nulla (la taglia massima reale e' gia' <= cap), lo
# zoom e' un no-op e viene saltato in silenzio per quella family (non
# duplica l'albero main).
# Esempio per aggiungerne uno nuovo:
#   {"slug": "zoom150", "max_size": 150, "label": "zoom fino a N=150"},
SIZE_ZOOMS = [
    {"slug": "zoom100", "max_size": 100, "label": "zoom fino a N=100"},
]


# ===========================================================================
def render_backend_tree(agg: pd.DataFrame, backend: str, base: Path, ground: pd.DataFrame | None,
                        *, variants: list[str] | None = None,
                        dir_suffix: str = "", label_suffix: str = "",
                        size_cap: int | None = None) -> int:
    variants = variants if variants is not None else MAIN_VARIANTS
    tree = base / f"graphs-{backend}"
    n = 0
    agg_b = agg[agg["backend"] == backend]
    for family in ("BSP", "PUP", "HRP"):
        agg_fb = agg_b[agg_b["family"] == family]
        if agg_fb.empty:
            continue
        if size_cap is not None:
            if agg_fb["size"].max() <= size_cap:
                continue  # nessun dato oltre il cap: identico all'albero main, non duplicarlo
            agg_fb = agg_fb[agg_fb["size"] <= size_cap]
        fam_dir = tree / f"{FAM_SUBDIR[family]}{dir_suffix}"
        # Overwrite pulito: se la cartella esiste gia' (run precedente, o slug
        # ridefinito con altre varianti escluse) la si butta e si riparte da
        # zero, cosi' non restano PNG orfani di una combinazione precedente.
        shutil.rmtree(fam_dir, ignore_errors=True)

        for metric in METRICS:
            if not metric.applies_to(backend):
                continue  # metrica di un altro backend: qui non e' un dato mancante
            if metric.key not in agg_fb.columns or agg_fb[metric.key].dropna().empty:
                continue
            fig, ax = plt.subplots(figsize=(8, 5.2))
            # anche le metriche del propagatore rispettano le esclusioni
            # dell'albero gemello: in "no_lc" lc non deve ricomparire qui.
            metric_variants = (_lazy_of(variants) if metric.lazy_only else variants)
            if _plot_metric_axis(ax, agg_fb, metric, family, variants=metric_variants,
                                 title=f"{family} — {metric.title} ({backend_label(backend)}){label_suffix}"):
                _save(fig, fam_dir / f"{metric.key}.png")
                n += 1
            else:
                plt.close(fig)

        n += _render_dashboard(agg_fb, family, backend, fam_dir, variants=variants, label_suffix=label_suffix)
        n += _render_ratio(agg_fb, family, backend, fam_dir, variants=variants, label_suffix=label_suffix)
        if ground is not None:
            n += _render_ground(ground, family, backend, fam_dir, agg_fb, variants=variants)
    return n


def _has_data(agg_fb: pd.DataFrame, key: str) -> bool:
    return key in agg_fb.columns and not agg_fb[key].dropna().empty


def _lazy_of(variants: list[str]) -> list[str]:
    """Varianti lazy fra quelle ammesse nell'albero corrente."""
    return [v for v in MAIN_LAZY_VARIANTS if v in variants]


def _render_dashboard(agg_fb: pd.DataFrame, family: str, backend: str, fam_dir: Path,
                      *, variants: list[str] | None = None, label_suffix: str = "") -> int:
    """DUE dashboard, non una.

    Metriche a scope "all" e metriche del propagatore rispondono a domande
    diverse e hanno un numero diverso di curve (5 varianti contro le sole 2
    lazy). Mescolarle nella stessa griglia (a) faceva una tavola da 26 pannelli
    illeggibile a qualunque dimensione di stampa, (b) invitava a leggere i
    pannelli a 2 curve come se ga/gc ci fossero "andate in timeout", mentre
    quelle metriche per le varianti non lazy non esistono proprio."""
    variants = variants if variants is not None else MAIN_VARIANTS
    lazy = _lazy_of(variants)
    core = [k for k in DASHBOARD_CORE
            if _has_data(agg_fb, k) and METRIC_BY_KEY[k].applies_to(backend)]
    extra = [k for k in DASHBOARD_EXTRA
             if _has_data(agg_fb, k) and METRIC_BY_KEY[k].applies_to(backend)]
    shared = [METRIC_BY_KEY[k] for k in core + extra if not METRIC_BY_KEY[k].lazy_only]
    prop = [METRIC_BY_KEY[k] for k in core + extra if METRIC_BY_KEY[k].lazy_only]

    n = _dashboard_grid(
        agg_fb, family, shared, variants=variants, lazy_variants=lazy,
        suptitle=f"{family} Dashboard — {backend_label(backend)}{label_suffix}",
        path=fam_dir / "_dashboard.png",
        # gli EXTRA ricominciano da una riga nuova, cosi' restano "accodati sotto"
        row_break_after=len([k for k in core if not METRIC_BY_KEY[k].lazy_only]))
    n += _dashboard_grid(
        agg_fb, family, prop, variants=variants, lazy_variants=lazy,
        suptitle=f"{family} Propagator dashboard (lazy variants only) "
                 f"— {backend_label(backend)}{label_suffix}",
        path=fam_dir / "_dashboard_propagator.png")
    return n


def _render_ratio(agg_fb: pd.DataFrame, family: str, backend: str, fam_dir: Path,
                  *, variants: list[str] | None = None, label_suffix: str = "") -> int:
    """Rapporto del solving lazy/standard per le coppie (gc,lc) e (ga,la).
    Valori > 1 => la variante lazy ha risolto piu' lentamente. Una coppia
    viene disegnata solo se ENTRAMBE le sue varianti sono ammesse (rispetta
    le esclusioni, es. niente (ga,la) nell'albero "no_ga")."""
    if "solving" not in agg_fb.columns:
        return 0
    allowed = set(variants) if variants is not None else set(MAIN_VARIANTS)
    piv = agg_fb.pivot_table(index="size", columns="setting", values="solving")
    fig, ax = plt.subplots(figsize=(8, 5))
    drew = False
    for std, lazy in (("gc", "lc"), ("ga", "la")):
        if std not in allowed or lazy not in allowed:
            continue
        if std in piv.columns and lazy in piv.columns:
            ratio = (piv[lazy] / piv[std]).dropna()
            if ratio.empty:
                continue
            # il rapporto "appartiene" alla variante lazy: ne eredita colore e
            # marker, cosi' resta riconoscibile accanto agli altri grafici.
            ax.plot(ratio.index, ratio.values,
                    **variant_kwargs(lazy, label=f"{label_of(lazy)} / {label_of(std)}"))
            drew = True
    if not drew:
        plt.close(fig)
        return 0
    ax.axhline(1.0, color="#888", linestyle="--", linewidth=1)
    ax.set_title(f"{family} — Lazy/Standard Solving-Time Ratio ({backend_label(backend)}){label_suffix}", fontsize=12, fontweight="bold")
    ax.set_xlabel(XLABEL.get(family, "size (N)"))
    ax.set_ylabel("lazy / standard solving time (x)")
    ax.grid(True, alpha=0.3, linestyle="--")
    ax.legend(fontsize=8)
    _save(fig, fam_dir / "lazy_standard_solving_time_ratio.png")
    return 1


def _render_ground(ground: pd.DataFrame, family: str, backend: str, fam_dir: Path,
                   agg_fb: pd.DataFrame, *, variants: list[str] | None = None) -> int:
    variants = variants if variants is not None else MAIN_VARIANTS
    g = ground[(ground["backend"] == backend) & (ground["family"] == family)].copy()
    if g.empty:
        return 0
    for col in ("ground_heuristics", "ground_lazy_heuristic_facts", "ground_query_heuristic_facts",
                "ground_prolog_heuristic_facts", "ground_lines", "size"):
        if col in g.columns:
            g[col] = pd.to_numeric(g[col], errors="coerce")
    g["combined_heuristics"] = (g.get("ground_heuristics", pd.Series(dtype=float)).fillna(0)
                                + g.get("ground_lazy_heuristic_facts", pd.Series(dtype=float)).fillna(0)
                                + g.get("ground_query_heuristic_facts", pd.Series(dtype=float)).fillna(0)
                                + g.get("ground_prolog_heuristic_facts", pd.Series(dtype=float)).fillna(0))
    gm = g.groupby(["variant", "size"], as_index=False)["combined_heuristics"].mean()
    n = 0
    for metric in (Metric("combined_heuristics", "Ground Heuristic Entities", "entities"),):
        fig, ax = plt.subplots(figsize=(8, 5.2))
        drew = False
        for v in variants:
            d = gm[gm["variant"] == v].dropna(subset=[metric.key]).sort_values("size")
            if d.empty or (d[metric.key] == 0).all():
                continue
            ax.plot(d["size"], d[metric.key], **variant_kwargs(v))
            drew = True
        if not drew:
            plt.close(fig)
            continue
        ax.set_title(f"{family} — {metric.title} ({backend_label(backend)})", fontsize=12, fontweight="bold")
        ax.set_xlabel(XLABEL.get(family, "size (N)"))
        ax.set_ylabel(metric.ylabel)
        ax.grid(True, alpha=0.3, linestyle="--")
        _apply_fmt(ax, metric)
        ax.legend(fontsize=7, ncol=2)
        _save(fig, fam_dir / f"{metric.key}.png")
        n += 1

    # scatter: grounding time (results.xml) vs combined heuristics (ground_counts)
    if "grounding" in agg_fb.columns:
        merged = pd.merge(
            agg_fb[["setting", "size", "grounding"]].rename(columns={"setting": "variant"}),
            gm[["variant", "size", "combined_heuristics"]], on=["variant", "size"], how="inner")
        merged = merged.dropna(subset=["grounding", "combined_heuristics"])
        if not merged.empty:
            fig, ax = plt.subplots(figsize=(8, 5.2))
            for v in variants:
                d = merged[merged["variant"] == v]
                if d.empty:
                    continue
                st = style_of(v)
                ax.scatter(d["combined_heuristics"], d["grounding"], s=40,
                           color=st.color, marker=st.marker,
                           edgecolor="white", linewidth=0.6, label=st.label)
            ax.set_title(f"{family} — Grounding Time vs Heuristic Objects ({backend_label(backend)})",
                         fontsize=12, fontweight="bold")
            ax.set_xlabel("combined ground heuristic objects")
            ax.set_ylabel("grounding time (s)")
            ax.grid(True, alpha=0.3, linestyle="--")
            ax.xaxis.set_major_formatter(FuncFormatter(_fmt_compact))
            ax.legend(fontsize=7, ncol=2)
            _save(fig, fam_dir / "grounding_time_vs_heuristic_size.png")
            n += 1
    return n


# ===========================================================================
# Albero esplorativo: studi mirati sulle varianti fuori dal confronto MAIN
# (la_co, la_aux, ga_weak). Layout:
#     graphs-<backend>/exploratory/<slug>/<famiglia>/{<metrica>.png, _dashboard.png}
# ===========================================================================
def render_exploratory_tree(agg: pd.DataFrame, backend: str, base: Path,
                            ground: pd.DataFrame | None) -> int:
    tree = base / f"graphs-{backend}" / "exploratory"
    n = 0
    agg_b = agg[agg["backend"] == backend]
    for study in EXPLORATORY_STUDIES:
        for family in ("BSP", "PUP", "HRP"):
            agg_fb = agg_b[agg_b["family"] == family]
            # senza almeno una variante esplorativa dello studio non c'e' nulla
            # di nuovo da dire: evita di duplicare i grafici principali.
            present = set(agg_fb["setting"].unique())
            expl = [v for v in study["variants"] if v not in MAIN_VARIANTS]
            if agg_fb.empty or not (present & set(expl)):
                continue
            fam_dir = tree / study["slug"] / FAM_SUBDIR[family]
            shutil.rmtree(fam_dir, ignore_errors=True)  # v. nota overwrite in render_backend_tree

            # stesso filtro degli alberi main: una metrica definita solo per
            # l'ALTRO backend qui non e' un dato mancante, non va disegnata.
            keys = [k for k in study["metrics"]
                    if _has_data(agg_fb, k) and METRIC_BY_KEY[k].applies_to(backend)]
            for k in keys:
                metric = METRIC_BY_KEY[k]
                # una metrica del propagatore ha senso solo sulle varianti lazy
                # dello studio: le g* non hanno un propagatore da misurare.
                study_variants = ([v for v in study["variants"] if v.startswith("l")]
                                  if metric.lazy_only else study["variants"])
                fig, ax = plt.subplots(figsize=(8, 5.2))
                if _plot_metric_axis(ax, agg_fb, metric, family, variants=study_variants,
                                     title=f"{family} — {metric.title} ({backend_label(backend)})\n"
                                           f"{study['title']}", title_width=90):
                    _save(fig, fam_dir / f"{metric.key}.png")
                    n += 1
                else:
                    plt.close(fig)

            n += _render_study_dashboard(agg_fb, family, backend, fam_dir, study, keys)
            if study.get("ground") and ground is not None:
                n += _render_ground(ground, family, backend, fam_dir, agg_fb,
                                    variants=study["variants"])
    return n


def _render_study_dashboard(agg_fb: pd.DataFrame, family: str, backend: str,
                            fam_dir: Path, study: dict, keys: list[str]) -> int:
    if not keys:
        return 0
    return _dashboard_grid(
        agg_fb, family, [METRIC_BY_KEY[k] for k in keys],
        variants=study["variants"],
        lazy_variants=[v for v in study["variants"] if v.startswith("l")],
        suptitle=f"{family} — {study['title']} ({backend_label(backend)})",
        path=fam_dir / "_dashboard.png", ncol=min(3, len(keys)))


# ===========================================================================
# Albero di confronto native-vs-prolog (+ verdetto del migliore per area)
# ===========================================================================
def _comparison_areas() -> list[str]:
    """Aree ammesse nell'albero di confronto: solo metriche definite su
    ENTRAMBI i backend. Il filtro e' automatico (sullo `scope` della metrica)
    invece che affidato alla disciplina di chi edita COMPARISON_AREAS: se in
    futuro qualcuno ci mette una metrica mono-backend, viene scartata qui con
    un avviso invece di finire in un grafico che confronta una curva con se
    stessa."""
    ok = []
    for area in COMPARISON_AREAS:
        metric = METRIC_BY_KEY.get(area)
        if metric is None:
            print(f"  [warn] area di confronto sconosciuta, ignorata: {area}")
            continue
        if len(metric.backends()) < 2:
            print(f"  [warn] '{area}' e' definita solo per il backend "
                  f"{metric.backends()[0]}: esclusa dal confronto native-vs-prolog")
            continue
        ok.append(area)
    return ok


# Stile del BACKEND nell'albero di confronto. Qui il tratto NON identifica piu'
# la variante (ci pensano colore e marker, invarianti): identifica il backend.
# native = linea piena e spessa con marker pieni; prolog = linea sottile
# tratteggiata con marker VUOTI, disegnata sopra. Cosi' quando le due curve
# coincidono al pixel — succede spesso, i due binari eseguono la stessa ricerca
# quando l'euristica decide le stesse cose — non si vede "solo native": si vede
# il tratteggio bianco sopra la linea piena e i marker a ciambella.
BACKEND_STYLE = {
    "native": {"dash": "solid", "linewidth": 2.6, "markersize": 6.5, "zorder": 2},
    "prolog": {"dash": (0, (4, 2.6)), "linewidth": 1.5, "markersize": 4.2, "zorder": 3},
}
# Soglia sotto la quale due curve sono dichiarate coincidenti (scarto relativo
# massimo sulle taglie in comune).
COINCIDENCE_TOL = 0.01


def render_comparison_tree(agg: pd.DataFrame, base: Path) -> tuple[int, dict]:
    tree = base / "graphs-comparison-native-prolog"
    n = 0
    verdicts: dict = {}
    areas = _comparison_areas()
    for family in ("BSP", "PUP", "HRP"):
        agg_f = agg[agg["family"] == family]
        if agg_f.empty:
            continue
        fam_dir = tree / FAM_SUBDIR[family]
        shutil.rmtree(fam_dir, ignore_errors=True)  # v. nota overwrite in render_backend_tree
        for area in areas:
            n += _plot_comparison_metric(agg_f, area, family, fam_dir)
        verdicts[family] = _verdict(agg_f, family, fam_dir, areas)
        n += 1  # verdict card
    return n, verdicts


def _series_by_backend(agg_f: pd.DataFrame, variant: str, area: str) -> dict[str, pd.Series]:
    """{backend: serie indicizzata per size} per una variante, senza NaN."""
    out = {}
    for backend in BACKENDS:
        d = agg_f[(agg_f["backend"] == backend) & (agg_f["setting"] == variant)]
        d = d.dropna(subset=[area]).sort_values("size")
        if not d.empty:
            out[backend] = pd.Series(d[area].to_numpy(), index=d["size"].to_numpy())
    return out


def _max_rel_gap(series: dict[str, pd.Series]) -> float | None:
    """Scarto relativo massimo fra native e prolog sulle taglie in comune.
    None se non c'e' niente da confrontare."""
    if not {"native", "prolog"}.issubset(series):
        return None
    nat, pro = series["native"], series["prolog"]
    common = nat.index.intersection(pro.index)
    if len(common) == 0:
        return None
    denom = nat[common].abs().clip(lower=1e-12)
    return float(((pro[common] - nat[common]).abs() / denom).max())


def _plot_comparison_metric(agg_f: pd.DataFrame, area: str, family: str, fam_dir: Path) -> int:
    if area not in agg_f.columns or agg_f[area].dropna().empty:
        return 0
    metric = METRIC_BY_KEY[area]
    # propagatore: ha senso solo sulle lazy; le altre metriche mostrano anche la
    # baseline gc, che e' il riferimento rispetto a cui i backend divergono.
    variants = MAIN_LAZY_VARIANTS if metric.lazy_only else ["gc", "la", "lc"]

    data = {v: _series_by_backend(agg_f, v, area) for v in variants}
    if not any(data.values()):
        return 0

    # Due pannelli: sopra le curve, sotto il rapporto prolog/native. Il pannello
    # inferiore risolve il caso peggiore — curve identiche e sovrapposte: una
    # riga piatta a 1.00 dice "i backend coincidono" senza doverlo dedurre da
    # due tracciati indistinguibili.
    has_ratio = any(_max_rel_gap(s) is not None for s in data.values())
    if has_ratio:
        fig, (ax, ax_r) = plt.subplots(
            2, 1, figsize=(8.8, 6.6), sharex=True,
            gridspec_kw={"height_ratios": [3.2, 1.0], "hspace": 0.08})
    else:
        fig, ax = plt.subplots(figsize=(8.8, 5.4))
        ax_r = None

    drew = False
    coincident: list[str] = []
    for v in variants:
        series = data[v]
        for backend in BACKENDS:
            if backend not in series:
                continue
            bs = BACKEND_STYLE[backend]
            s = series[backend]
            ax.plot(s.index, s.to_numpy(),
                    **variant_kwargs(
                        v, dash=bs["dash"], linewidth=bs["linewidth"],
                        markersize=bs["markersize"], zorder=bs["zorder"],
                        # marker vuoti per prolog: sovrapposto a native resta
                        # visibile l'anello colorato sopra il marker pieno.
                        markerfacecolor="white" if backend == "prolog" else style_of(v).color,
                        markeredgecolor=style_of(v).color if backend == "prolog" else "white",
                        markeredgewidth=1.1 if backend == "prolog" else 0.6,
                        label=f"{label_of(v)} · {backend_short(backend)}"))
            drew = True

        gap = _max_rel_gap(series)
        if gap is not None and gap < COINCIDENCE_TOL:
            coincident.append(label_of(v))
        if ax_r is not None and gap is not None:
            nat, pro = series["native"], series["prolog"]
            common = nat.index.intersection(pro.index)
            ratio = pro[common] / nat[common].replace(0, float("nan"))
            ax_r.plot(common, ratio.to_numpy(),
                      **variant_kwargs(v, dash="solid", linewidth=1.6, markersize=4,
                                       label=label_of(v)))

    if not drew:
        plt.close(fig)
        return 0

    ax.set_title(f"{family} — {metric.title}: C++ vs Prolog", fontsize=12, fontweight="bold")
    ax.set_ylabel(metric.ylabel)
    ax.grid(True, alpha=0.3, linestyle="--")
    _apply_fmt(ax, metric)
    # titolo della legenda su tre righe: in una sola era piu' largo del
    # riquadro delle voci e allargava la legenda su meta' del grafico.
    ax.legend(fontsize=7, ncol=2,
              title="colour + marker = variant\n"
                    "solid line / filled markers = C++\n"
                    "dashed line / hollow markers = Prolog",
              title_fontsize=6.5)

    # Dichiarare la coincidenza e' piu' onesto (e piu' leggibile) che sperare
    # che si distinguano due tracciati sovrapposti.
    if coincident:
        ax.text(0.005, 0.985,
                "C++ ≡ Prolog (Δ < 1%): " + ", ".join(coincident),
                transform=ax.transAxes, fontsize=7, va="top", ha="left", color="#2C3E50",
                bbox={"boxstyle": "round,pad=0.32", "facecolor": "#FCF3CF",
                      "edgecolor": "#F1C40F", "linewidth": 0.7})

    if ax_r is not None:
        ax_r.axhline(1.0, color="#7F8C8D", linestyle="--", linewidth=1)
        ax_r.set_ylabel("Prolog / C++", fontsize=8)
        ax_r.set_xlabel(XLABEL.get(family, "size (N)"))
        ax_r.grid(True, alpha=0.3, linestyle="--")
        ax_r.tick_params(labelsize=8)
        # il rapporto arriva a 5 cifre (ms_per_decide su HRP): senza formato
        # compatto le etichette dell'asse sono piu' larghe del pannello.
        ax_r.yaxis.set_major_locator(MaxNLocator(nbins=4))
        ax_r.yaxis.set_major_formatter(FuncFormatter(_fmt_compact))
        ax_r.legend(fontsize=6.5, ncol=3)
    else:
        ax.set_xlabel(XLABEL.get(family, "size (N)"))

    _scope_note(ax_r if ax_r is not None else ax, metric)
    _save(fig, fam_dir / f"{area}.png")
    return 1


# ---------------------------------------------------------------------------
# Tabelle PNG. matplotlib da' colonne di larghezza uniforme e righe tutte
# uguali: su una tabella con una colonna lunga ("RIASSUNTO PER AREA",
# "total_propagator_time_ms") il testo esce dalla cella e diventa illeggibile.
# Qui le larghezze sono proporzionali al contenuto piu' lungo di ogni colonna,
# la figura e' dimensionata di conseguenza e le righe sono zebrate.
# ---------------------------------------------------------------------------
TABLE_STYLE = {
    "header_bg": "#2C3E50",
    "header_fg": "#FFFFFF",
    "row_bg": ("#FFFFFF", "#EEF2F5"),      # zebratura
    "section_bg": "#D5DBDB",
    "grid": "#B0BEC5",
    "win_native": "#D5F5E3",
    "win_prolog": "#D6EAF8",
    "win_tie": "#FDEBD0",
    "muted": "#7F8C8D",
}
_CHAR_W = 0.095      # pollici per carattere a fontsize 9 (stima prudente)
_ROW_H = 0.30        # pollici per riga


def _render_table(rows: list[list[str]], *, title: str, subtitle: str = "",
                  align: list[str] | None = None,
                  section_rows: set[int] | None = None,
                  cell_colors: dict[tuple[int, int], str] | None = None,
                  path: Path) -> None:
    """`rows[0]` e' l'intestazione. Indici in `section_rows`/`cell_colors` sono
    riferiti a `rows` (0 = header)."""
    ncol = max(len(r) for r in rows)
    rows = [list(r) + [""] * (ncol - len(r)) for r in rows]
    section_rows = section_rows or set()
    cell_colors = cell_colors or {}
    align = align or ["center"] * ncol

    # larghezza per colonna = contenuto piu' lungo (header incluso), con un
    # minimo perche' una colonna di 1-2 caratteri non collassi.
    widths_ch = [max(4, max(len(r[j]) for r in rows) + 2) for j in range(ncol)]
    total_ch = sum(widths_ch)
    col_widths = [w / total_ch for w in widths_ch]

    fig_w = max(7.0, total_ch * _CHAR_W)
    # sottotitolo a capo sulla larghezza della tabella: su una riga sola era
    # piu' largo della figura (il crop di savefig si allargava fino a lui,
    # facendo sembrare la tabella minuscola) e finiva sopra il titolo.
    sub_lines = textwrap.wrap(subtitle, max(60, int(fig_w / _CHAR_W) - 4)) if subtitle else []
    fig_h = 0.95 + 0.16 * len(sub_lines) + _ROW_H * len(rows)
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    ax.axis("off")
    # il titolo sta SOPRA il sottotitolo: il suo pad deve scavalcarlo tutto.
    ax.set_title(title, fontsize=12.5, fontweight="bold", pad=14 + 10.5 * len(sub_lines))
    if sub_lines:
        ax.annotate("\n".join(sub_lines), xy=(0.5, 1.0), xycoords="axes fraction",
                    xytext=(0, 6), textcoords="offset points", fontsize=8,
                    color=TABLE_STYLE["muted"], ha="center", va="bottom")

    tbl = ax.table(cellText=rows, colWidths=col_widths, loc="center", cellLoc="center")
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(9)
    tbl.scale(1, 1.35)

    for (i, j), cell in tbl.get_celld().items():
        cell.set_edgecolor(TABLE_STYLE["grid"])
        cell.set_linewidth(0.5)
        if i == 0:
            cell.set_facecolor(TABLE_STYLE["header_bg"])
            cell.set_text_props(color=TABLE_STYLE["header_fg"], fontweight="bold")
            cell.set_height(cell.get_height() * 1.15)
            continue
        if i in section_rows:
            cell.set_facecolor(TABLE_STYLE["section_bg"])
            cell.set_text_props(fontweight="bold")
        else:
            cell.set_facecolor(TABLE_STYLE["row_bg"][i % 2])
        cell.set_text_props(ha=align[j])
        # padding coerente con l'allineamento, altrimenti il testo tocca il bordo
        cell.PAD = 0.04
        if align[j] == "left":
            cell.get_text().set_x(0.03)
        elif align[j] == "right":
            cell.get_text().set_x(0.97)

    for (i, j), color in cell_colors.items():
        if (i, j) in tbl.get_celld():
            tbl[i, j].set_facecolor(color)

    _save(fig, path)


_WIN_COLOR = {
    "native": TABLE_STYLE["win_native"],
    "C++": TABLE_STYLE["win_native"],
    "prolog": TABLE_STYLE["win_prolog"],
    "Prolog": TABLE_STYLE["win_prolog"],
    "tie": TABLE_STYLE["win_tie"],
}


def _fmt_delta(rel: float) -> str:
    """Scarto relativo leggibile. Oltre il 999% si passa al fattore (x12) e poi
    a un cappuccio: una cella con "+16764612000000000.0%" sfonda la colonna e
    non aggiunge informazione rispetto a ">> 1000x"."""
    if abs(rel) < 1e-4:
        return "≈ 0%"
    if abs(rel) < 9.99:
        return f"{rel * 100:+.1f}%"
    factor = 1.0 + abs(rel)
    if factor < 1000:
        return f"{'+' if rel > 0 else '-'}{factor:.0f}x"
    return f"{'>' if rel > 0 else '<'} 1000x"


def _fmt_value(metric: Metric, value: float) -> str:
    """Numero leggibile nella tabella: GB per la memoria, compatto per i
    conteggi, 3 cifre significative per i tempi."""
    if metric.fmt == "gb":
        return f"{value / 1024.0:.2f} GB"
    if metric.fmt == "compact":
        return _fmt_compact(value)
    return f"{value:.3g}"


def _verdict(agg_f: pd.DataFrame, family: str, fam_dir: Path,
             areas: list[str] | None = None) -> dict:
    """Per ogni area e variante lazy, decreta il backend migliore (valore piu'
    basso) all'ULTIMA taglia comune risolta da entrambi. Rende una tabella PNG
    e un dict riassuntivo {area: native|prolog|pari|n/d}."""
    areas = areas if areas is not None else _comparison_areas()
    rows: list[tuple] = []
    summary: dict = {}
    for area in areas:
        if area not in agg_f.columns:
            continue
        metric = METRIC_BY_KEY[area]
        wins = {"C++": 0, "Prolog": 0, "tie": 0}
        compared = 0
        for v in MAIN_LAZY_VARIANTS:
            nat = agg_f[(agg_f["backend"] == "native") & (agg_f["setting"] == v)].dropna(subset=[area])
            pro = agg_f[(agg_f["backend"] == "prolog") & (agg_f["setting"] == v)].dropna(subset=[area])
            common = sorted(set(nat["size"]) & set(pro["size"]))
            if not common:
                continue
            s = common[-1]
            nv = float(nat[nat["size"] == s][area].iloc[0])
            pv = float(pro[pro["size"] == s][area].iloc[0])
            # "pari" non e' solo l'uguaglianza esatta: sotto la tolleranza di
            # coincidenza le due misure sono lo stesso numero col rumore.
            rel = abs(pv - nv) / max(abs(nv), 1e-12)
            if rel < COINCIDENCE_TOL:
                winner = "tie"
            else:
                winner = "C++" if nv < pv else "Prolog"
            wins[winner] += 1
            compared += 1
            rows.append((metric, area, v, s, nv, pv, rel if pv >= nv else -rel, winner))
        if compared == 0:
            summary[area] = "n/a"                     # nessuna taglia comune
        elif wins["C++"] == wins["Prolog"]:
            summary[area] = "tie"
        else:
            summary[area] = "C++" if wins["C++"] > wins["Prolog"] else "Prolog"

    header = ["Area", "Variant", "N", "C++", "Prolog", "Δ Prolog / C++", "Better"]
    table_rows: list[list[str]] = [header]
    cell_colors: dict[tuple[int, int], str] = {}
    section_rows: set[int] = set()

    for metric, area, v, s, nv, pv, rel, winner in rows:
        table_rows.append([metric.title, label_of(v), str(s),
                           _fmt_value(metric, nv), _fmt_value(metric, pv),
                           _fmt_delta(rel), winner])
        cell_colors[(len(table_rows) - 1, 6)] = _WIN_COLOR.get(winner, "#FFFFFF")

    section_rows.add(len(table_rows))
    table_rows.append(["SUMMARY BY AREA", "", "", "", "", "", ""])
    for area, w in summary.items():
        table_rows.append([METRIC_BY_KEY[area].title, "", "", "", "", "", w])
        cell_colors[(len(table_rows) - 1, 6)] = _WIN_COLOR.get(w, "#FFFFFF")

    _render_table(
        table_rows,
        title=f"{family} — Verdict: C++ vs Prolog",
        subtitle="compared at the largest size N solved by BOTH backends  ·  "
                 f"the lower value wins  ·  gap < {COINCIDENCE_TOL:.0%} = tie  ·  "
                 "n/a = no common size (or metric not measured on one backend)",
        align=["left", "left", "right", "right", "right", "right", "center"],
        section_rows=section_rows,
        cell_colors=cell_colors,
        path=fam_dir / "_verdict.png",
    )
    return summary


# ===========================================================================
# Albero di confronto CLINGO vs ALPHA (graphs-comparison-clingo-alpha/)
#
# Domanda a cui risponde: quanto costa ottenere la semantica ad aggregati
# dinamici dentro un pipeline ground-and-solve (le varianti la/ga di questa
# tesi) rispetto a prenderla da chi la implementa nativamente (Alpha Qh)?
#
# COSA SI PUO' CONFRONTARE, E PERCHE' SOLO QUESTO
# clingo e Alpha non condividono NESSUN contatore interno: clasp conta
# choices/conflicts, Alpha conta chiamate al grounder e backtrack, e le due
# cose non misurano lo stesso fenomeno. Non c'e' nemmeno una separazione
# grounding/solving da confrontare, perche' nel lazy grounding le due fasi
# sono interleavate per costruzione. Restano confrontabili solo le grandezze
# misurate DALL'ESTERNO, da runlim, sullo stesso identico strumento per
# entrambi i sistemi: wall-clock e picco di RSS. Sono poche, ma sono le
# uniche che reggono in tesi; i contatori interni di Alpha finiscono in un
# pannello a parte, dichiarato come tale.
#
# ATTENZIONE alla memoria: per Alpha il processo e' una JVM e `mem` include
# l'heap RISERVATO, non quello usato (v. resultparsers/alpha.py). Il grafico
# risponde a "quanto costa eseguire questo sistema", non a "quanto stato
# tiene l'algoritmo". La nota e' stampata sul grafico stesso, non solo qui.
# ===========================================================================
ALPHA_TREE_NAME = "graphs-comparison-clingo-alpha"

# Famiglie del confronto. HRP c'e' dal 2026-08-08: l'encoding Alpha degli
# autori esiste (paper sulle euristiche domain-specific, Case Study 1) ed e'
# in encodings-alpha/3_HRP/. Attenzione a cosa misura pero': su HRP le
# euristiche NON usano aggregati dinamici, quindi la famiglia confronta
# ground-and-solve contro lazy grounding a parita' di euristica — e' il
# controllo che separa i due effetti che BSP e PUP misurano insieme.
# V. il commento sopra <system name="alpha-qh"> in runscripts/runscript.xml.
ALPHA_FAMILIES = ("BSP", "PUP", "HRP")

# Le varianti clingo messe a confronto. Si usa il solo backend native: il
# confronto native-vs-prolog e' gia' un'altra macroarea, e ficcare qui anche
# il gemello prolog raddoppierebbe le curve senza rispondere alla domanda.
ALPHA_VS_CLINGO_VARIANTS = ["gc_noheur", "gc", "ga", "la", "lc"]
# alpha_dom esiste solo su HRP: dove manca sparisce da solo dai grafici, e
# nella frontiera compare come "lanciata e mai riuscita" solo se il
# runscript l'ha davvero eseguita (v. attempted_settings).
ALPHA_OWN_VARIANTS = ["alpha", "alpha_dom", "alpha_noheur"]

# Metriche misurate da runlim: le uniche confrontabili fra i due sistemi.
ALPHA_SHARED_METRICS = ["time", "mem"]

# {famiglia: metriche da disegnare in scala LOG}. Su HRP i TEMPI dei sistemi in
# campo stanno su quattro ordini di grandezza (0.2 s per le varianti ground di
# clingo, 14.7 s per Alpha Qh, 441 s per `lc`): in lineare la curva piu' alta
# appiattisce tutte le altre sull'asse e la figura non mostra proprio il
# confronto per cui esiste. La memoria della stessa famiglia resta LINEARE
# (2.4 GB il massimo: si legge benissimo, e in log i pochi MB delle varianti
# clingo diventano un pettine di picchi verso il fondo scala). BSP e PUP sono
# lineari su entrambe: sono le figure gia' in tesi e li' le curve sono dello
# stesso ordine.
ALPHA_LOG_METRICS = {"HRP": {"time"}}


def _as_log(metric: Metric) -> Metric:
    """Copia della metrica con asse y logaritmico (i Metric sono globali e
    condivisi: mutarli qui cambierebbe anche gli altri alberi)."""
    return Metric(metric.key, metric.title, metric.ylabel,
                  scope=metric.scope, fmt=metric.fmt, log=True)

# Contatori interni di Alpha. Vivono in un pannello separato e NON sono
# affiancati a choices/conflicts di clasp.
ALPHA_INTERNAL_METRICS = [
    # g = guess del solver, non chiamate al grounder: v. il commento in
    # resultparsers/alpha.py, verificato sul sorgente di Alpha.
    Metric("alpha_g", "Alpha: Guesses", "guesses", fmt="compact"),
    Metric("alpha_bt", "Alpha: Backtracks", "bt", fmt="compact"),
    Metric("alpha_prolog_query_ms", "Alpha: Heuristic Query Time", "Time (ms)", fmt="compact"),
    Metric("alpha_ms_per_query", "Alpha: Cost per Heuristic Query", "ms / query"),
]

_ALPHA_MEM_NOTE = ("Alpha runs on the JVM: its peak RSS includes the heap RESERVED "
                   "via -Xmx, not only the heap in use. It measures the cost of RUNNING "
                   "the system, not the state the algorithm holds.")


def _alpha_slice(agg: pd.DataFrame, family: str) -> pd.DataFrame:
    """Righe del confronto per una famiglia: varianti clingo sul backend
    native + i due setting di Alpha, con `setting` gia' pronto a fare da
    chiave di stile (i nomi non collidono: alpha/alpha_noheur non esistono
    fra le varianti clingo)."""
    fam = agg[agg["family"] == family]
    clingo = fam[(fam["backend"] == "native") & (fam["setting"].isin(ALPHA_VS_CLINGO_VARIANTS))]
    alpha = fam[(fam["backend"] == ALPHA_BACKEND) & (fam["setting"].isin(ALPHA_OWN_VARIANTS))]
    return pd.concat([clingo, alpha], ignore_index=True)


def _plot_alpha_frontier(agg_f: pd.DataFrame, family: str, path: Path,
                         *, attempted: set[str] | None = None) -> int:
    """Taglia massima risolta da ciascun sistema. `agg` contiene solo i run
    RISOLTI (v. aggregate()), quindi il massimo di `size` per variante E' la
    frontiera: nessun conteggio di timeout da rifare a mano.

    `attempted` = le varianti effettivamente LANCIATE per questa famiglia. Chi
    non ha risolto NIENTE (nemmeno l'istanza piu' piccola) sparisce da `agg` e
    prima spariva anche dal grafico: su PUP mancava del tutto `alpha_noheur`,
    dando l'impressione che non fosse stato provato invece che il contrario —
    ha fallito ovunque. Ora resta con una barra a 0, che e' il suo risultato."""
    known = ALPHA_VS_CLINGO_VARIANTS + ALPHA_OWN_VARIANTS
    solved = set(agg_f["setting"].unique())
    variants = [v for v in known if v in solved or (attempted and v in attempted)]
    if not variants:
        return 0
    reach = [float(agg_f[agg_f["setting"] == v]["size"].max()) if v in solved else 0.0
             for v in variants]

    fig, ax = plt.subplots(figsize=(8.8, 4.6))
    ax.bar(range(len(variants)), reach,
           color=[style_of(v).color for v in variants], edgecolor="white", linewidth=0.8)
    for i, val in enumerate(reach):
        ax.text(i, val, f"{val:g}" if val else "0 — none",
                ha="center", va="bottom", fontsize=8,
                color="#2C3E50" if val else "#C0392B",
                fontweight="normal" if val else "bold")
    ax.set_xticks(range(len(variants)))
    ax.set_xticklabels([_wrap(label_of(v), 18) for v in variants],
                       rotation=25, ha="right", fontsize=7.5)
    ax.set_ylabel(f"largest {XLABEL.get(family, 'size (N)')} solved", fontsize=9)
    ax.set_title(f"{family} — largest instance solved", fontsize=11, fontweight="bold")
    ax.grid(True, axis="y", alpha=0.3, linestyle="--")
    note = ("frontier within the campaign limits (runscript timeout/memout); "
            "it is a lower bound, not the largest instance solvable in absolute terms")
    if any(r == 0 for r in reach):
        note += ".  0 = launched but no instance solved, not even the smallest"
    fig.subplots_adjust(bottom=0.30)
    _figure_note(fig, note, reserve=False, y=0.02)
    _save(fig, path)
    return 1


def render_alpha_tree(agg: pd.DataFrame, base: Path,
                      attempted: dict[tuple[str, str], set[str]] | None = None) -> int:
    """graphs-comparison-clingo-alpha/<FAM>/{time,mem,frontier,_alpha_internals,_dashboard}.png

    `attempted` (v. attempted_settings) serve solo alla frontiera, per
    distinguere "non lanciata" da "lanciata e mai riuscita"."""
    if ALPHA_BACKEND not in set(agg["backend"].unique()):
        print(f"  [info] nessun run '{ALPHA_BACKEND}' in results.xml: "
              f"albero {ALPHA_TREE_NAME} saltato")
        return 0

    tree = base / ALPHA_TREE_NAME
    n = 0
    for family in ALPHA_FAMILIES:
        agg_f = _alpha_slice(agg, family)
        if agg_f.empty:
            continue
        # Senza righe Alpha per QUESTA famiglia non c'e' un confronto da fare:
        # _alpha_slice restituirebbe le sole varianti clingo e uscirebbe un
        # "clingo vs Alpha" con dentro solo clingo. Capita ogni volta che si
        # aggiunge una famiglia ad ALPHA_FAMILIES prima di aver rilanciato la
        # campagna (HRP, 2026-08-08): meglio saltarla dicendolo.
        if agg_f[agg_f["backend"] == ALPHA_BACKEND].empty:
            print(f"  [info] {family}: nessun run '{ALPHA_BACKEND}' in questi risultati "
                  f"(campagna precedente all'aggiunta della famiglia?): "
                  f"cartella {FAM_SUBDIR[family]} saltata in {ALPHA_TREE_NAME}")
            continue
        fam_dir = tree / FAM_SUBDIR[family]
        # overwrite pulito, come negli altri alberi: una variante rimossa dal
        # runscript non deve sopravvivere come PNG del run precedente.
        shutil.rmtree(fam_dir, ignore_errors=True)

        present = [v for v in ALPHA_VS_CLINGO_VARIANTS + ALPHA_OWN_VARIANTS
                   if v in set(agg_f["setting"].unique())]

        log_keys = ALPHA_LOG_METRICS.get(family, set())
        shared = [_as_log(METRIC_BY_KEY[k]) if k in log_keys else METRIC_BY_KEY[k]
                  for k in ALPHA_SHARED_METRICS]
        log_scale = bool(log_keys)
        log_note = ("logarithmic y axis where the panel needs it: on this family the systems "
                    "span four orders of magnitude and a linear axis would flatten all but the largest.")

        for metric in shared:
            key = metric.key
            fig, ax = plt.subplots(figsize=(8.8, 5.4))
            drew = _plot_metric_axis(ax, agg_f, metric, family, variants=present,
                                     title=f"{family} — {metric.title}: Clingo (C++) vs Alpha")
            if drew:
                # una sola nota per figura: due _figure_note si scriverebbero
                # alla stessa y, una sopra l'altra.
                notes = ([_ALPHA_MEM_NOTE] if key == "mem" else []) + \
                        ([log_note] if metric.log else [])
                if notes:
                    _figure_note(fig, "  ".join(notes))
                _save(fig, fam_dir / f"{key}.png")
                n += 1
            else:
                plt.close(fig)

        fam_attempted = set()
        for be in (ALPHA_BACKEND, "native"):
            fam_attempted |= set((attempted or {}).get((be, family), set()))
        n += _plot_alpha_frontier(agg_f, family, fam_dir / "frontier.png",
                                  attempted=fam_attempted)

        # Pannello dei contatori interni di Alpha: solo righe alpha-qh, e
        # dichiarato in titolo come non confrontabile con clingo.
        alpha_only = agg_f[agg_f["setting"].isin(ALPHA_OWN_VARIANTS)]
        internals = [m for m in ALPHA_INTERNAL_METRICS
                     if m.key in alpha_only.columns and not alpha_only[m.key].dropna().empty]
        if internals:
            alpha_present = [v for v in ALPHA_OWN_VARIANTS
                             if v in set(alpha_only["setting"].unique())]
            n += _dashboard_grid(
                alpha_only, family, internals,
                variants=alpha_present, lazy_variants=alpha_present,
                suptitle=f"{family} — Alpha internal counters "
                         f"(NOT comparable with clasp's counters)",
                path=fam_dir / "_alpha_internals.png", ncol=2, panel=(6.0, 4.0))

        # Dashboard: le due metriche condivise affiancate, che e' la figura
        # che serve in tesi.
        n += _dashboard_grid(
            agg_f, family, shared,
            variants=present, lazy_variants=present,
            suptitle=f"{family} — Clingo (C++) vs Alpha (runlim measures, the only comparable ones)",
            path=fam_dir / "_dashboard.png", ncol=len(ALPHA_SHARED_METRICS),
            panel=(6.4, 4.9),
            extra_notes=[_ALPHA_MEM_NOTE] + ([log_note] if log_scale else []))
    return n


# ===========================================================================
# Albero MOTORE PROLOG: Alpha Qh vs il backend Prolog di questa tesi
# (graphs-comparison-alpha-prolog/)
#
# Domanda a cui risponde: due sistemi diversi hanno risolto lo STESSO problema
# — valutare un'euristica dichiarativa interrogando un motore Prolog su
# un'immagine dell'assegnamento parziale — con due implementazioni indipendenti.
# Quanto costa l'una e quanto l'altra?
#
# PERCHE' QUESTO CONFRONTO E' LECITO E QUELLO SUI CONTATORI DI RICERCA NO
# Nell'albero clingo-vs-Alpha (sopra) sono confrontabili solo le misure di
# runlim, perche' guesses/backtracks e choices/conflicts contano fenomeni
# diversi. Qui la situazione e' l'opposto e va detta esplicitamente: Alpha Qh e
# il backend Prolog implementano lo stesso meccanismo, quindi il COSTO DI UNA
# CONSULTAZIONE e la QUOTA DI RUN passata dentro il motore misurano la stessa
# cosa nei due sistemi e si confrontano direttamente. Restano invece NON
# confrontabili i CONTEGGI: Alpha interroga intorno ai propri guess, il
# propagatore una volta per decisione di clasp. Il numero e' disegnato lo
# stesso — serve a spiegare i totali — ma la nota in calce dichiara che sono
# eventi diversi.
#
# Tutte e tre le famiglie hanno i dati: sono gli stessi run della campagna
# (system alpha-qh + system clingo-prolog), nessuna misura aggiuntiva.
# ===========================================================================
ENGINE_TREE_NAME = "graphs-comparison-alpha-prolog"

# Lato Alpha solo il setting "alpha": e' l'unico con -uqh, cioe' l'unico che
# usa davvero il bridge Prolog. alpha_dom (HRP) valuta le euristiche nello
# store nativo e infatti non emette alcuna metrica di query: sparisce da solo.
ENGINE_ALPHA_VARIANT = "alpha"
# Lato nostro le due varianti lazy del confronto principale, entrambe sul
# backend prolog: `la` e' il regime "poche consultazioni ben guidate", `lc`
# quello "tante consultazioni inutili", e insieme coprono le due estremita' del
# costo che Alpha si trova nel mezzo.
ENGINE_PROLOG_VARIANTS = ["la", "lc"]

ENGINE_METRICS = [
    # conteggi e tempi cumulati: `lc` ne fa fino a tre ordini di grandezza piu'
    # degli altri (73.143 consultazioni su HRP-14 contro 106 di `la`), e su
    # scala lineare schiaccerebbe le altre due curve sull'asse. Log.
    Metric("engine_consultations", "Consultations of the Prolog Engine",
           "consultations", fmt="compact", log=True),
    Metric("engine_ms_per_consultation", "Cost of One Consultation", "ms / consultation"),
    Metric("engine_total_s", "Cumulative Time Inside the Prolog Engine",
           "Time (s)", log=True),
    Metric("engine_share_pct", "Share of the Run Spent in the Prolog Engine", "% of wall time"),
]

_ENGINE_NOTES = [
    "clingo curves (la/lc) are the PROLOG backend; the C++ backend has no query phase and does not appear here.",
    "counts are NOT commensurable: Alpha queries around its own guesses, the propagator once per clasp decision. "
    "The commensurable measures are the cost of one consultation and the share of the run spent inside the engine.",
    "share = cumulative query time / runlim wall time, same definition for both systems: for the clingo variants "
    "the denominator includes the grounding of the base program, which Alpha never performs.",
    "counts and cumulative times are on a LOGARITHMIC axis: the curves differ by up to three orders of magnitude.",
]


def _engine_frame(agg: pd.DataFrame, family: str) -> pd.DataFrame:
    """Righe (setting, size) con le quattro metriche del motore, prese dalle
    colonne dei due sistemi e riportate a chiavi comuni: Alpha le emette come
    alpha_prolog_*, il propagatore come total_prolog_query_time_ms/decide_calls.
    Senza questa normalizzazione le due serie non finirebbero mai sullo stesso
    asse, che e' esattamente il confronto che serve."""
    fam = agg[agg["family"] == family]
    rows = []

    def _add(setting: str, size, count, ms, total_ms, wall):
        if pd.isna(count) or pd.isna(total_ms):
            return
        rows.append({
            "setting": setting, "family": family, "size": size,
            "engine_consultations": count,
            "engine_ms_per_consultation": ms if not pd.isna(ms) else (
                total_ms / count if count else float("nan")),
            "engine_total_s": total_ms / 1000.0,
            "engine_share_pct": (100.0 * total_ms / 1000.0 / wall
                                 if wall and not pd.isna(wall) and wall > 0 else float("nan")),
        })

    for _, r in fam[(fam["backend"] == ALPHA_BACKEND)
                    & (fam["setting"] == ENGINE_ALPHA_VARIANT)].iterrows():
        _add(ENGINE_ALPHA_VARIANT, r["size"], r.get("alpha_prolog_queries"),
             r.get("alpha_ms_per_query"), r.get("alpha_prolog_query_ms"), r.get("time"))

    for _, r in fam[(fam["backend"] == "prolog")
                    & (fam["setting"].isin(ENGINE_PROLOG_VARIANTS))].iterrows():
        _add(r["setting"], r["size"], r.get("decide_calls"),
             r.get("prolog_ms_per_decide"), r.get("total_prolog_query_time_ms"), r.get("time"))

    return pd.DataFrame(rows)


def render_engine_tree(agg: pd.DataFrame, base: Path) -> int:
    """graphs-comparison-alpha-prolog/<FAM>/{<metrica>.png, _dashboard.png}"""
    if ALPHA_BACKEND not in set(agg["backend"].unique()):
        print(f"  [info] nessun run '{ALPHA_BACKEND}' in results.xml: "
              f"albero {ENGINE_TREE_NAME} saltato")
        return 0
    if "prolog" not in set(agg["backend"].unique()):
        print(f"  [info] nessun run sul backend prolog: albero {ENGINE_TREE_NAME} saltato")
        return 0

    tree = base / ENGINE_TREE_NAME
    n = 0
    for family in ALPHA_FAMILIES:
        frame = _engine_frame(agg, family)
        if frame.empty:
            print(f"  [info] {family}: nessuna metrica di query nei due sistemi, "
                  f"cartella saltata in {ENGINE_TREE_NAME}")
            continue
        present = [v for v in [ENGINE_ALPHA_VARIANT] + ENGINE_PROLOG_VARIANTS
                   if v in set(frame["setting"].unique())]
        if len(present) < 2:
            print(f"  [info] {family}: un solo sistema con dati di query "
                  f"({present}), non c'e' un confronto da disegnare")
            continue

        fam_dir = tree / FAM_SUBDIR[family]
        shutil.rmtree(fam_dir, ignore_errors=True)

        for metric in ENGINE_METRICS:
            fig, ax = plt.subplots(figsize=(8.8, 5.4))
            drew = _plot_metric_axis(
                ax, frame, metric, family, variants=present, note=False,
                title=f"{family} — {metric.title}: Alpha Qh vs Prolog backend")
            if drew:
                _figure_note(fig, _ENGINE_NOTES[1])
                _save(fig, fam_dir / f"{metric.key.replace('engine_', '')}.png")
                n += 1
            else:
                plt.close(fig)

        n += _dashboard_grid(
            frame, family, ENGINE_METRICS,
            variants=present, lazy_variants=present,
            suptitle=f"{family} — two implementations of the same idea: "
                     f"Alpha's Qh bridge vs this thesis's Prolog backend",
            path=fam_dir / "_dashboard.png", ncol=2, panel=(6.4, 4.6),
            extra_notes=_ENGINE_NOTES)
    return n


# ===========================================================================
# Cartella riassuntiva "colpo d'occhio": copia (rinominata) di OGNI dashboard
# gia' generata altrove — albero main, ogni albero di esclusione varianti
# (VARIANT_EXCLUSIONS: no_ga, no_ga_lc, ...), ogni zoom di scala (SIZE_ZOOMS:
# zoom100, ...), ogni studio esplorativo (EXPLORATORY_STUDIES), per ciascun
# backend/famiglia — piu' i 3 verdetti native-vs-prolog, sotto
# <base>/riassunto_grafici/.
#
# NON piatta: una cartella sola con ~50 PNG e' illeggibile quanto la vecchia
# dashboard da 26 pannelli — per confrontare due grafici della stessa
# macroarea bisognava riconoscerli dal prefisso del nome. Qui c'e' una
# sottocartella per MACROAREA (v. SUMMARY_AREAS) e, dentro le due macroaree
# grosse (un albero per backend), una per famiglia: cosi' ogni foglia ha una
# manciata di file e i nomi non devono piu' portare tutto il contesto.
# Sono COPIE (shutil.copy2): gli originali restano al loro posto nei
# rispettivi alberi graphs-*/. L'elenco e' costruito DINAMICAMENTE da
# BACKENDS/VARIANT_EXCLUSIONS/SIZE_ZOOMS/EXPLORATORY_STUDIES invece che da una
# lista statica: aggiungendo una nuova esclusione, zoom o studio esplorativo
# (come gia' successo con "no_ga_lc") il riassunto li include da solo, senza
# toccare questa funzione. Combinazioni senza dati (es. uno studio
# esplorativo disponibile solo per BSP, o uno zoom che per una family e' un
# no-op) vengono saltate in silenzio.
# ===========================================================================
SUMMARY_DIR_NAME = "riassunto_grafici"

# Una sottocartella per macroarea. Numerate nell'ordine in cui si guardano
# (prima le varianti dentro un backend, poi i due confronti, poi gli studi
# esplorativi), cosi' l'ordinamento alfabetico del file manager coincide con
# l'ordine di lettura.
SUMMARY_AREAS = {
    "native": "1_varianti-native",
    "prolog": "2_varianti-prolog",
    "comparison": "3_native-vs-prolog",
    "alpha": "4_clingo-vs-alpha",
    "engine": "5_alpha-vs-backend-prolog",
    "exploratory": "6_esplorativi",
}

SUMMARY_AREA_DESC = {
    "1_varianti-native": "le 5 varianti a confronto sul backend native, una cartella per famiglia",
    "2_varianti-prolog": "le 5 varianti a confronto sul backend prolog, una cartella per famiglia",
    "3_native-vs-prolog": "verdetto per area: quale backend vince, all'ultima taglia comune",
    "4_clingo-vs-alpha": "confronto col sistema esterno Alpha (tutte le famiglie di ALPHA_FAMILIES)",
    "5_alpha-vs-backend-prolog": "costo del motore Prolog nei due sistemi che lo usano: Alpha Qh e il nostro backend",
    "6_esplorativi": "studi mirati sulle varianti fuori dal confronto principale",
}


def _summary_sources(base: Path) -> list[tuple[Path, Path]]:
    """[(percorso RELATIVO dentro riassunto_grafici, sorgente da copiare)]."""
    sources: list[tuple[Path, Path]] = []
    for backend in BACKENDS:
        area = Path(SUMMARY_AREAS.get(backend, backend))
        expl_area = Path(SUMMARY_AREAS["exploratory"])
        tree = base / f"graphs-{backend}"
        for family in ("BSP", "PUP", "HRP"):
            fam_dir = FAM_SUBDIR[family]
            dst = area / fam_dir
            sources.append((dst / "main.png", tree / fam_dir / "_dashboard.png"))
            # la dashboard del propagatore solo per l'albero main: nelle
            # esclusioni/zoom cambia poco (toccano soprattutto le varianti non
            # lazy) e riempirebbe il riassunto di copie quasi identiche.
            sources.append((dst / "main_propagatore.png",
                            tree / fam_dir / "_dashboard_propagator.png"))
            for excl in VARIANT_EXCLUSIONS:
                sources.append((dst / f"{excl['slug']}.png",
                                tree / f"{fam_dir}-{excl['slug']}" / "_dashboard.png"))
            for zoom in SIZE_ZOOMS:
                sources.append((dst / f"{zoom['slug']}.png",
                                tree / f"{fam_dir}-{zoom['slug']}" / "_dashboard.png"))
            for study in EXPLORATORY_STUDIES:
                # gli esplorativi sono raggruppati per STUDIO, non per backend:
                # la domanda e' "cosa dice questo studio", e le due risposte
                # (native/prolog) vanno lette una accanto all'altra.
                sources.append((expl_area / study["slug"] / f"{fam_dir}_{backend}.png",
                                tree / "exploratory" / study["slug"] / fam_dir / "_dashboard.png"))
    cmp_area = Path(SUMMARY_AREAS["comparison"])
    for family in ("BSP", "PUP", "HRP"):
        sources.append((cmp_area / f"{FAM_SUBDIR[family]}_verdetto.png",
                        base / "graphs-comparison-native-prolog" / FAM_SUBDIR[family] / "_verdict.png"))
    alpha_area = Path(SUMMARY_AREAS["alpha"])
    for family in ALPHA_FAMILIES:
        fam_dir = FAM_SUBDIR[family]
        sources.append((alpha_area / f"{fam_dir}_dashboard.png",
                        base / ALPHA_TREE_NAME / fam_dir / "_dashboard.png"))
        sources.append((alpha_area / f"{fam_dir}_frontiera.png",
                        base / ALPHA_TREE_NAME / fam_dir / "frontier.png"))
    engine_area = Path(SUMMARY_AREAS["engine"])
    for family in ALPHA_FAMILIES:
        fam_dir = FAM_SUBDIR[family]
        sources.append((engine_area / f"{fam_dir}_dashboard.png",
                        base / ENGINE_TREE_NAME / fam_dir / "_dashboard.png"))
        sources.append((engine_area / f"{fam_dir}_costo_consultazione.png",
                        base / ENGINE_TREE_NAME / fam_dir / "ms_per_consultation.png"))
    return sources


def _write_summary_index(out_dir: Path, copied: list[Path]) -> None:
    """_INDICE.txt: cosa c'e' in ogni sottocartella e da quale albero viene.
    Una cartella di sole PNG non puo' spiegarsi da sola, e il riassunto e' il
    primo posto dove si va a guardare a distanza di mesi."""
    lines = ["RIASSUNTO GRAFICI — copie delle dashboard/verdetti dai vari alberi graphs-*/",
             "Generato da tools/plot_results.py (job 'summary'). Gli originali restano",
             "nei rispettivi alberi: qui c'e' solo il colpo d'occhio, organizzato per",
             "macroarea.", ""]
    for area, desc in SUMMARY_AREA_DESC.items():
        files = sorted(p for p in copied if p.parts[0] == area)
        if not files:
            continue
        lines.append(f"{area}/  — {desc}")
        for p in files:
            lines.append(f"    {p.relative_to(area)}")
        lines.append("")
    (out_dir / "_INDICE.txt").write_text("\n".join(lines), encoding="utf-8")


def render_summary(base: Path) -> int:
    """Raccoglie in <base>/riassunto_grafici/<macroarea>/ tutte le dashboard e i
    verdetti gia' prodotti da render_backend_tree/render_exploratory_tree/
    render_comparison_tree/render_alpha_tree (v. _summary_sources)."""
    out_dir = base / SUMMARY_DIR_NAME
    # overwrite pulito: se uno slug/studio e' stato rinominato o rimosso da
    # VARIANT_EXCLUSIONS/EXPLORATORY_STUDIES, la copia vecchia non deve restare.
    shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    copied: list[Path] = []
    for rel, src in _summary_sources(base):
        if not src.exists():
            continue
        dst = out_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied.append(rel)
    _write_summary_index(out_dir, copied)
    return len(copied)


# ===========================================================================
# Registro dei job indipendenti: ogni entry scrive in una sua sottocartella
# (nessuna sovrascrittura incrociata tra job diversi), cosi' da poter essere
# lanciata da un processo/nodo SLURM separato via `--only <job_id>` — vedi
# 6_plot_graphs_hpc.sh nella root del repo, che sottomette un array di job
# (uno per id qui sotto) e fa watch fino al completamento.
# "summary" fa eccezione: DIPENDE dall'aver gia' completato tutti i "*:main"
# + "comparison" (copia le loro PNG), va eseguito per ultimo.
# Oltre a "<backend>:main"/"<backend>:exploratory"/"<backend>:excl:<slug>" ci
# sono anche "<backend>:zoom:<slug>" (uno per ogni SIZE_ZOOMS): stesso albero
# main ma con la scala (size) limitata, per leggere meglio i casi in cui una
# sola variante scala molto oltre le altre. Sono job "di plotting puro": non
# serve rieseguire i benchmark per aggiungerne uno nuovo, basta rilanciare
# 6_plot_graphs_hpc.sh (funziona anche in locale, v. quel file) sugli stessi
# results.xml/xlsx gia' scaricati.
# ===========================================================================
def build_jobs(agg: pd.DataFrame, base: Path, ground: pd.DataFrame | None,
               attempted: dict[tuple[str, str], set[str]] | None = None
               ) -> tuple[dict[str, Callable[[], int]], list[str], dict]:
    jobs: dict[str, Callable[[], int]] = {}
    order: list[str] = []
    state: dict = {"verdicts": {}}

    for backend in BACKENDS:
        if backend not in set(agg["backend"].unique()):
            continue

        jobs[f"{backend}:main"] = lambda b=backend: render_backend_tree(agg, b, base, ground)
        order.append(f"{backend}:main")

        jobs[f"{backend}:exploratory"] = lambda b=backend: render_exploratory_tree(agg, b, base, ground)
        order.append(f"{backend}:exploratory")

        for excl in VARIANT_EXCLUSIONS:
            exset = _exclude_set(excl)

            def _run_excl(b=backend, exset=exset, excl=excl) -> int:
                variants = [v for v in MAIN_VARIANTS if v not in exset]
                return render_backend_tree(agg, b, base, ground, variants=variants,
                                           dir_suffix=f"-{excl['slug']}",
                                           label_suffix=f" — {excl['label']}")

            jid = f"{backend}:excl:{excl['slug']}"
            jobs[jid] = _run_excl
            order.append(jid)

        for zoom in SIZE_ZOOMS:

            def _run_zoom(b=backend, zoom=zoom) -> int:
                return render_backend_tree(agg, b, base, ground,
                                           dir_suffix=f"-{zoom['slug']}",
                                           label_suffix=f" — {zoom['label']}",
                                           size_cap=zoom["max_size"])

            jid = f"{backend}:zoom:{zoom['slug']}"
            jobs[jid] = _run_zoom
            order.append(jid)

    def _run_comparison() -> int:
        n, verdicts = render_comparison_tree(agg, base)
        state["verdicts"] = verdicts
        return n

    jobs["comparison"] = _run_comparison
    order.append("comparison")

    # Job indipendente: gira su un suo nodo SLURM come gli altri, e se in
    # results.xml non ci sono run di Alpha si limita a stampare un [info].
    # Cosi' una campagna vecchia (senza il system alpha-qh) continua a
    # funzionare senza modifiche.
    jobs["alpha-comparison"] = lambda: render_alpha_tree(agg, base, attempted)
    order.append("alpha-comparison")

    # Stessa logica: senza run Alpha (o senza backend prolog) stampa un [info]
    # e non disegna niente, cosi' i results.xml vecchi restano validi.
    jobs["alpha-prolog-engines"] = lambda: render_engine_tree(agg, base)
    order.append("alpha-prolog-engines")

    jobs["summary"] = lambda: render_summary(base)
    order.append("summary")

    return jobs, order, state


def _print_job_result(jid: str, n: int) -> None:
    print(f"  [{jid}] {n} PNG/file")


# ===========================================================================
def main() -> None:
    here = Path(__file__).resolve().parents[1]          # benchmark_folder_clingo
    ap = argparse.ArgumentParser(description="Grafici dai risultati benchmark-tool.")
    ap.add_argument("--results", type=Path, default=here / "results.xml")
    ap.add_argument("--machine", default="local")
    ap.add_argument("--out-base", type=Path, default=here.parent,  # default: test_folder/
                    help="cartella che conterra' i tre alberi di grafici")
    ap.add_argument("--ground-counts", type=Path, default=None,
                    help="output/ground_counts.csv per i grafici di grounding")
    ap.add_argument("--list-jobs", action="store_true",
                    help="stampa gli id dei job indipendenti (uno per riga) ed esce, "
                         "senza disegnare nulla — usato da 6_plot_graphs_hpc.sh per "
                         "sapere quanti job SLURM sottomettere")
    ap.add_argument("--only", default=None, metavar="JOB_ID",
                    help="esegue SOLO il job indicato (v. --list-jobs) invece della "
                         "pipeline completa; utile per parallelizzare su piu' nodi")
    args = ap.parse_args()

    if not args.results.exists():
        raise SystemExit(
            f"results.xml non trovato: {args.results}\n"
            "Genera prima i risultati:  btool eval runscripts/runscript.xml > results.xml")

    tidy = load_tidy(args.results)
    if tidy.empty:
        raise SystemExit("results.xml non contiene run: niente da disegnare.")
    agg = aggregate(tidy, args.machine)
    if agg.empty:
        raise SystemExit(f"Nessun run risolto per machine={args.machine}.")

    ground = None
    if args.ground_counts and args.ground_counts.exists():
        ground = pd.read_csv(args.ground_counts)

    base = args.out_base
    base.mkdir(parents=True, exist_ok=True)

    jobs, order, state = build_jobs(agg, base, ground, attempted_settings(tidy, args.machine))

    if args.list_jobs:
        for jid in order:
            print(jid)
        return

    print(f"Aggregato: {len(agg)} righe  backend={sorted(agg['backend'].unique())}  "
          f"famiglie={sorted(agg['family'].unique())}  machine={args.machine}")

    if args.only:
        if args.only not in jobs:
            raise SystemExit(
                f"job sconosciuto: {args.only!r}. Job disponibili (--list-jobs):\n  "
                + "\n  ".join(order))
        n = jobs[args.only]()
        _print_job_result(args.only, n)
        if args.only == "comparison" and state["verdicts"]:
            print("\nVERDETTO native vs prolog (per area):")
            for fam, summ in state["verdicts"].items():
                print(f"  {fam}: " + "  ".join(f"{a}={w}" for a, w in summ.items()))
        return

    # Nessun --only: pipeline completa e sequenziale (comportamento storico).
    # Per l'esecuzione parallela su HPC vedi 6_plot_graphs_hpc.sh, che
    # sottomette un job SLURM per ciascun id di `order` (tranne "summary",
    # lanciato per ultimo perche' dipende dagli altri).
    total = 0
    for jid in order:
        n = jobs[jid]()
        total += n
        _print_job_result(jid, n)

    if state["verdicts"]:
        print("\nVERDETTO native vs prolog (per area):")
        for fam, summ in state["verdicts"].items():
            print(f"  {fam}: " + "  ".join(f"{a}={w}" for a, w in summ.items()))
    print(f"\nTotale PNG: {total}  (in {base}/)")


if __name__ == "__main__":
    main()
