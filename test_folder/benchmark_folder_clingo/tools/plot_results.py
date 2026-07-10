#!/usr/bin/env python3
"""Grafici dai risultati di benchmark-tool (suite "Lazy Heuristics / Dynamic Aggregates").

Sorgente dati: il file XML prodotto da
    btool eval runscripts/runscript.xml > results.xml
Contiene TUTTE le misure del resultparser custom (resultparsers/clasp.py):
status/timeout/memout, time(wall), mem(picco RSS), solving, grounding,
clingo_total, choices, conflicts, restarts, rules, variables, e — per le
varianti lazy sul backend prolog — decide_calls e i tempi del propagatore
(total_prolog_query_time_ms, total_decide_time_ms, ...).

Produce TRE alberi di grafici, una sottocartella per famiglia (1_BSP/2_PUP/3_HRP):

    <out-base>/graphs-native/                varianti MAIN, backend native
    <out-base>/graphs-prolog/                varianti MAIN, backend prolog
    <out-base>/graphs-comparison-native-prolog/   native vs prolog (varianti lazy),
                                             con "verdetto" del migliore per area

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
import xml.etree.ElementTree as ET
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

# ---------------------------------------------------------------------------
# Theming per variante (riusa lo schema della vecchia suite). La prima lettera
# del nome = approccio (g* ground-and-solve, l* lazy); l'ultima = semantica
# (*c clingo-like, *a alpha-like).
# ---------------------------------------------------------------------------
VARIANT_LABELS = {
    "gc_noheur": "G&S Clingo (no heur)",
    "gc": "G&S Clingo",
    "ga": "G&S Alpha",
    "ga_weak": "G&S Alpha (weak)",
    "la": "Lazy Alpha",
    "lc": "Lazy Clingo",
    "la_aux": "Lazy Alpha + Aux",
    "la_co": "Lazy Alpha + ConstrOpt",
}
VARIANT_COLORS = {
    "gc_noheur": "#34495E", "gc": "#E74C3C", "ga": "#F39C12", "ga_weak": "#D68910",
    "la": "#2ECC71", "lc": "#9B59B6", "la_aux": "#16A085", "la_co": "#3498DB",
}
VARIANT_MARKERS = {
    "gc_noheur": "X", "gc": "o", "ga": "^", "ga_weak": "v",
    "la": "o", "lc": "s", "la_aux": "^", "la_co": "D",
}
VARIANT_LINESTYLES = {
    "gc_noheur": ":", "gc": "--", "ga": "--", "ga_weak": "--",
    "la": "-", "lc": "-", "la_aux": "-", "la_co": "-.",
}
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
        "title": "la_co: linearizzazione del vincolo e impatto sul grounding",
        "variants": ["gc", "la", "lc", "la_co"],
        "metrics": ["grounding", "solving", "clingo_total", "mem", "rules", "constraints"],
        "ground": True,
    },
    {
        "slug": "la_aux_vs_gs",
        "title": "la_aux: comportamento ground-and-solve forzato (atteso ~gc)",
        "variants": ["gc_noheur", "gc", "ga", "la", "la_aux"],
        "metrics": ["grounding", "solving", "clingo_total", "mem",
                    "choices", "conflicts", "decide_calls"],
        "ground": False,
    },
    {
        "slug": "ga_vs_ga_weak",
        "title": "ga vs ga_weak: unrolling degli aggregati vs sola negazione-as-alpha",
        "variants": ["gc_noheur", "gc", "ga", "ga_weak", "la", "lc"],
        "metrics": ["grounding", "solving", "clingo_total", "mem",
                    "choices", "conflicts", "rules", "constraints"],
        "ground": False,
    },
]

XLABEL = {"BSP": "Problem size (N)", "PUP": "Instance size (N)", "HRP": "Instance size (persons N)"}


# ---------------------------------------------------------------------------
# Metriche da results.xml. Tutte "lower is better". lazy_only=True: definite
# solo per le varianti lazy sul backend prolog (propagatore query-driven).
# ---------------------------------------------------------------------------
class Metric:
    def __init__(self, key, title, ylabel, *, lazy_only=False, fmt="auto"):
        self.key = key
        self.title = title
        self.ylabel = ylabel
        self.lazy_only = lazy_only
        self.fmt = fmt


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
    Metric("decide_calls", "Propagator Decide Calls", "decide_calls", lazy_only=True, fmt="compact"),
    Metric("total_prolog_query_time_ms", "Total Prolog Query Time", "Time (ms)", lazy_only=True, fmt="compact"),
    Metric("prolog_ms_per_decide", "Prolog Query Cost per Decision", "ms / decide", lazy_only=True),
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
    Metric("total_decide_time_ms", "Total Decide Time", "Time (ms)", lazy_only=True, fmt="compact"),
    Metric("total_state_sync_time_ms", "State Sync Time", "Time (ms)", lazy_only=True, fmt="compact"),
    Metric("total_candidate_scan_time_ms", "Candidate Scan Time", "Time (ms)", lazy_only=True, fmt="compact"),
    Metric("total_literal_lookup_time_ms", "Literal Lookup Time", "Time (ms)", lazy_only=True, fmt="compact"),
    Metric("total_candidate_selection_time_ms", "Candidate Selection Time", "Time (ms)", lazy_only=True, fmt="compact"),
    Metric("total_candidates_seen", "Total Candidates Seen", "candidates", lazy_only=True, fmt="compact"),
    Metric("avg_candidates_per_decide", "Avg Candidates per Decide", "candidates / decide", lazy_only=True),
]
METRICS = METRICS + EXTRA_METRICS
METRIC_BY_KEY = {m.key: m for m in METRICS}

# Aree del confronto native-vs-prolog ("le varie aree").
COMPARISON_AREAS = ["solving", "grounding", "clingo_total", "mem", "decide_calls", "prolog_ms_per_decide"]

# Dashboard per-backend: una "immagine generale" con tutto. I pannelli CORE
# stanno in alto; gli EXTRA vengono ACCODATI sotto (righe finali), nell'ordine.
DASHBOARD_CORE = ["grounding", "solving", "clingo_total", "mem",
                  "choices", "conflicts", "restarts", "solving_ms_per_choice"]
DASHBOARD_EXTRA = ["rules", "variables", "atoms", "constraints", "time",
                   "decide_calls", "total_prolog_query_time_ms", "prolog_ms_per_decide",
                   "total_decide_time_ms", "total_state_sync_time_ms",
                   "total_candidate_scan_time_ms", "total_literal_lookup_time_ms",
                   "total_candidate_selection_time_ms", "total_candidates_seen",
                   "avg_candidates_per_decide"]

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

    # derivate per-run
    if {"solving", "choices"}.issubset(wide.columns):
        wide["solving_ms_per_choice"] = 1000.0 * wide["solving"] / wide["choices"].where(wide["choices"] > 0)
    if {"total_prolog_query_time_ms", "decide_calls"}.issubset(wide.columns):
        wide["prolog_ms_per_decide"] = (
            wide["total_prolog_query_time_ms"] / wide["decide_calls"].where(wide["decide_calls"] > 0))

    value_cols = [c for c in wide.columns
                  if c not in ("backend", "setting", "family", "size", "instance", "run")]
    agg = (wide.groupby(["backend", "setting", "family", "size"])[value_cols]
                .median().reset_index())
    return agg


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


def _apply_fmt(ax, metric: Metric):
    if metric.fmt == "gb":
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6))
        ax.yaxis.set_major_formatter(FuncFormatter(_fmt_gb_from_mb))
    elif metric.fmt == "compact":
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6))
        ax.yaxis.set_major_formatter(FuncFormatter(_fmt_compact))
    ax.yaxis.offsetText.set_visible(False)


# ===========================================================================
# Disegno di una singola metrica (una curva per variante)
# ===========================================================================
def _variants_present(agg_fb: pd.DataFrame, allowed: list[str] | None = None) -> list[str]:
    """Varianti presenti nei dati, nell'ordine canonico. Di default filtra
    alle sole MAIN_VARIANTS: le esplorative si ottengono passando `allowed`."""
    present = set(agg_fb["setting"].unique())
    order = allowed if allowed is not None else MAIN_VARIANTS
    return [v for v in order if v in present]


def _plot_metric_axis(ax, agg_fb: pd.DataFrame, metric: Metric, family: str, *, variants=None) -> bool:
    if metric.key not in agg_fb.columns:
        ax.text(0.5, 0.5, "metrica assente", transform=ax.transAxes, ha="center", va="center", color="#AAA")
        ax.set_title(metric.title, fontsize=11, fontweight="bold")
        return False
    variants = variants if variants is not None else _variants_present(agg_fb)
    drew = False
    for v in variants:
        d = agg_fb[agg_fb["setting"] == v].dropna(subset=[metric.key]).sort_values("size")
        if d.empty:
            continue
        ax.plot(d["size"], d[metric.key],
                color=VARIANT_COLORS.get(v, "#555"), marker=VARIANT_MARKERS.get(v, "o"),
                linestyle=VARIANT_LINESTYLES.get(v, "-"), linewidth=1.8, markersize=4,
                markeredgecolor="white", markeredgewidth=0.6,
                label=VARIANT_LABELS.get(v, v))
        drew = True
    ax.set_title(metric.title, fontsize=11, fontweight="bold")
    ax.set_xlabel(XLABEL.get(family, "size (N)"), fontsize=9)
    ax.set_ylabel(metric.ylabel, fontsize=9)
    ax.grid(True, alpha=0.3, linestyle="--")
    _apply_fmt(ax, metric)
    if drew:
        ax.legend(fontsize=7, ncol=2)
    return drew


def _save(fig, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=140, bbox_inches="tight")
    plt.close(fig)


# ===========================================================================
# Alberi per-backend (graphs-native / graphs-prolog)
# ===========================================================================
# Esclusione varianti: per ogni entry qui sotto, in AGGIUNTA all'albero
# normale (tutte le MAIN_VARIANTS), viene generato un secondo albero completo
# (stessi metrics + dashboard + ratio + ground) con la variante indicata
# tolta dai grafici — utile quando una variante ha una scala/andamento cosi'
# diverso dalle altre da schiacciarle nel plot (es. "ga": G&S Alpha).
# Cartella gemella: "<FAM_SUBDIR>-<slug>" (es. "1_BSP-no_ga"), stesso livello
# di "1_BSP" dentro graphs-native/ e graphs-prolog/.
# Estendibile in futuro: basta aggiungere altre entry a questa lista, il
# resto della pipeline (render_backend_tree e le funzioni _render_*) legge
# gia' `variants`/`dir_suffix`/`label_suffix` in modo generico.
VARIANT_EXCLUSIONS = [
    {"slug": "no_ga", "exclude": "ga", "label": "senza G&S Alpha (ga)"},
]


# ===========================================================================
def render_backend_tree(agg: pd.DataFrame, backend: str, base: Path, ground: pd.DataFrame | None,
                        *, variants: list[str] | None = None,
                        dir_suffix: str = "", label_suffix: str = "") -> int:
    variants = variants if variants is not None else MAIN_VARIANTS
    tree = base / f"graphs-{backend}"
    n = 0
    agg_b = agg[agg["backend"] == backend]
    for family in ("BSP", "PUP", "HRP"):
        agg_fb = agg_b[agg_b["family"] == family]
        if agg_fb.empty:
            continue
        fam_dir = tree / f"{FAM_SUBDIR[family]}{dir_suffix}"

        for metric in METRICS:
            if metric.key not in agg_fb.columns or agg_fb[metric.key].dropna().empty:
                continue
            fig, ax = plt.subplots(figsize=(8, 5.2))
            metric_variants = MAIN_LAZY_VARIANTS if metric.lazy_only else variants
            if _plot_metric_axis(ax, agg_fb, metric, family, variants=metric_variants):
                fig.suptitle(f"{family} — {metric.title} ({backend}){label_suffix}",
                            fontsize=12, fontweight="bold")
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


def _render_dashboard(agg_fb: pd.DataFrame, family: str, backend: str, fam_dir: Path,
                      *, variants: list[str] | None = None, label_suffix: str = "") -> int:
    variants = variants if variants is not None else MAIN_VARIANTS
    core = [k for k in DASHBOARD_CORE if _has_data(agg_fb, k)]
    extra = [k for k in DASHBOARD_EXTRA if _has_data(agg_fb, k)]
    keys = core + extra
    if not keys:
        return 0
    ncol = 4
    # allinea l'inizio degli EXTRA a una nuova riga, cosi' restano "accodati sotto".
    pad = (-len(core)) % ncol if extra else 0
    panels = core + [None] * pad + extra
    nrow = math.ceil(len(panels) / ncol)
    fig, axes = plt.subplots(nrow, ncol, figsize=(4.6 * ncol, 3.4 * nrow), squeeze=False)
    flat = axes.flatten()
    for ax, k in zip(flat, panels):
        if k is None:
            ax.axis("off")
            continue
        metric = METRIC_BY_KEY[k]
        _plot_metric_axis(ax, agg_fb, metric, family,
                          variants=MAIN_LAZY_VARIANTS if metric.lazy_only else variants)
    for ax in flat[len(panels):]:
        ax.axis("off")
    # separatore visivo tra blocco CORE e blocco EXTRA accodato (solo la riga,
    # senza etichetta testuale al centro)
    if extra and pad >= 0:
        sep_y = 1.0 - (len(core) + pad) / ncol / nrow
        fig.add_artist(plt.Line2D([0.02, 0.98], [sep_y, sep_y], transform=fig.transFigure,
                                  color="#BBB", linewidth=1.2, linestyle="--"))
    fig.suptitle(f"{family} Dashboard — {backend}{label_suffix}", fontsize=15, fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    _save(fig, fam_dir / "_dashboard.png")
    return 1


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
            ax.plot(ratio.index, ratio.values, marker="o", markersize=4,
                    color=VARIANT_COLORS.get(lazy, "#555"), label=f"{lazy} / {std}")
            drew = True
    if not drew:
        plt.close(fig)
        return 0
    ax.axhline(1.0, color="#888", linestyle="--", linewidth=1)
    ax.set_title(f"{family} — Lazy/Standard Solving-Time Ratio ({backend}){label_suffix}", fontsize=12, fontweight="bold")
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
                                + g.get("ground_query_heuristic_facts", pd.Series(dtype=float)).fillna(0))
    gm = g.groupby(["variant", "size"]).median(numeric_only=True).reset_index()
    n = 0
    for metric in GROUND_METRICS:
        if metric.key not in gm.columns or gm[metric.key].dropna().empty:
            continue
        fig, ax = plt.subplots(figsize=(8, 5.2))
        drew = False
        for v in variants:
            d = gm[gm["variant"] == v].dropna(subset=[metric.key]).sort_values("size")
            if d.empty or (d[metric.key] == 0).all():
                continue
            ax.plot(d["size"], d[metric.key], color=VARIANT_COLORS.get(v, "#555"),
                    marker=VARIANT_MARKERS.get(v, "o"), linestyle=VARIANT_LINESTYLES.get(v, "-"),
                    linewidth=1.8, markersize=4, label=VARIANT_LABELS.get(v, v))
            drew = True
        if not drew:
            plt.close(fig)
            continue
        ax.set_title(f"{family} — {metric.title} ({backend})", fontsize=12, fontweight="bold")
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
                ax.scatter(d["combined_heuristics"], d["grounding"], s=36,
                           color=VARIANT_COLORS.get(v, "#555"), marker=VARIANT_MARKERS.get(v, "o"),
                           edgecolor="white", linewidth=0.6, label=VARIANT_LABELS.get(v, v))
            ax.set_title(f"{family} — Grounding Time vs Heuristic Objects ({backend})",
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

            keys = [k for k in study["metrics"] if _has_data(agg_fb, k)]
            for k in keys:
                metric = METRIC_BY_KEY[k]
                fig, ax = plt.subplots(figsize=(8, 5.2))
                if _plot_metric_axis(ax, agg_fb, metric, family, variants=study["variants"]):
                    fig.suptitle(f"{family} — {metric.title} ({backend})\n{study['title']}",
                                 fontsize=11, fontweight="bold")
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
    ncol = min(3, len(keys))
    nrow = math.ceil(len(keys) / ncol)
    fig, axes = plt.subplots(nrow, ncol, figsize=(4.6 * ncol, 3.4 * nrow), squeeze=False)
    flat = axes.flatten()
    for ax, k in zip(flat, keys):
        _plot_metric_axis(ax, agg_fb, METRIC_BY_KEY[k], family, variants=study["variants"])
    for ax in flat[len(keys):]:
        ax.axis("off")
    fig.suptitle(f"{family} — {study['title']} ({backend})", fontsize=13, fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    _save(fig, fam_dir / "_dashboard.png")
    return 1


# ===========================================================================
# Albero di confronto native-vs-prolog (+ verdetto del migliore per area)
# ===========================================================================
def render_comparison_tree(agg: pd.DataFrame, base: Path) -> tuple[int, dict]:
    tree = base / "graphs-comparison-native-prolog"
    n = 0
    verdicts: dict = {}
    for family in ("BSP", "PUP", "HRP"):
        agg_f = agg[agg["family"] == family]
        if agg_f.empty:
            continue
        fam_dir = tree / FAM_SUBDIR[family]
        for area in COMPARISON_AREAS:
            n += _plot_comparison_metric(agg_f, area, family, fam_dir)
        verdicts[family] = _verdict(agg_f, family, fam_dir)
        n += 1  # verdict card
    return n, verdicts


def _plot_comparison_metric(agg_f: pd.DataFrame, area: str, family: str, fam_dir: Path) -> int:
    if area not in agg_f.columns or agg_f[area].dropna().empty:
        return 0
    metric = METRIC_BY_KEY[area]
    if metric.lazy_only:
        variants = MAIN_LAZY_VARIANTS     # propagatore: solo prolog ha dati
    else:
        variants = ["gc", "la", "lc"]     # baseline + le lazy (dove i backend divergono)
    fig, ax = plt.subplots(figsize=(8.4, 5.4))
    drew = False
    for v in variants:
        for backend, ls, alpha in (("native", "-", 1.0), ("prolog", "--", 0.9)):
            d = agg_f[(agg_f["backend"] == backend) & (agg_f["setting"] == v)]
            d = d.dropna(subset=[area]).sort_values("size")
            if d.empty:
                continue
            ax.plot(d["size"], d[area], color=VARIANT_COLORS.get(v, "#555"),
                    linestyle=ls, alpha=alpha, marker=VARIANT_MARKERS.get(v, "o"),
                    markersize=4, linewidth=1.8,
                    label=f"{VARIANT_LABELS.get(v, v)} · {backend}")
            drew = True
    if not drew:
        plt.close(fig)
        return 0
    ax.set_title(f"{family} — {metric.title}: native vs prolog", fontsize=12, fontweight="bold")
    ax.set_xlabel(XLABEL.get(family, "size (N)"))
    ax.set_ylabel(metric.ylabel)
    ax.grid(True, alpha=0.3, linestyle="--")
    _apply_fmt(ax, metric)
    ax.legend(fontsize=7, ncol=2, title="solida=native · tratteggio=prolog", title_fontsize=7)
    _save(fig, fam_dir / f"{area}.png")
    return 1


def _verdict(agg_f: pd.DataFrame, family: str, fam_dir: Path) -> dict:
    """Per ogni area e variante lazy, decreta il backend migliore (valore piu'
    basso) all'ULTIMA taglia comune risolta da entrambi. Rende una tabella PNG
    e un dict riassuntivo {area: native|prolog|pari|solo-prolog|n/d}."""
    rows = []
    summary: dict = {}
    for area in COMPARISON_AREAS:
        if area not in agg_f.columns:
            continue
        metric = METRIC_BY_KEY[area]
        if metric.lazy_only:
            summary[area] = "solo-prolog"
            continue
        wins = {"native": 0, "prolog": 0, "pari": 0}
        compared = 0
        for v in ["la", "lc"]:
            nat = agg_f[(agg_f["backend"] == "native") & (agg_f["setting"] == v)].dropna(subset=[area])
            pro = agg_f[(agg_f["backend"] == "prolog") & (agg_f["setting"] == v)].dropna(subset=[area])
            common = sorted(set(nat["size"]) & set(pro["size"]))
            if not common:
                continue
            s = common[-1]
            nv = float(nat[nat["size"] == s][area].iloc[0])
            pv = float(pro[pro["size"] == s][area].iloc[0])
            winner = "native" if nv < pv else ("prolog" if pv < nv else "pari")
            wins[winner] += 1
            compared += 1
            rows.append((area, v, s, nv, pv, winner))
        if compared == 0:
            summary[area] = "n/d"                     # nessuna taglia comune
        elif wins["native"] == wins["prolog"]:
            summary[area] = "pari"
        else:
            summary[area] = "native" if wins["native"] > wins["prolog"] else "prolog"

    fig, ax = plt.subplots(figsize=(8.6, 0.6 + 0.42 * (len(rows) + len(summary) + 3)))
    ax.axis("off")
    ax.set_title(f"{family} — Verdetto native vs prolog (ultima taglia comune)",
                 fontsize=12, fontweight="bold", pad=12)
    table_rows = [["Area", "Variante", "N", "native", "prolog", "Migliore"]]
    for area, v, s, nv, pv, w in rows:
        table_rows.append([area, v, str(s), f"{nv:.3g}", f"{pv:.3g}", w])
    table_rows.append(["", "", "", "", "", ""])
    table_rows.append(["RIASSUNTO PER AREA", "", "", "", "", ""])
    for area, w in summary.items():
        table_rows.append([area, "", "", "", "", w])
    tbl = ax.table(cellText=table_rows, cellLoc="center", loc="center")
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(8)
    tbl.scale(1, 1.3)
    for j in range(6):
        tbl[0, j].set_facecolor("#34495E")
        tbl[0, j].set_text_props(color="white", fontweight="bold")
    for i, row in enumerate(table_rows[1:], start=1):
        w = row[-1]
        if w == "native":
            tbl[i, 5].set_facecolor("#D5F5E3")
        elif w == "prolog":
            tbl[i, 5].set_facecolor("#D6EAF8")
    _save(fig, fam_dir / "_verdict.png")
    return summary


# ===========================================================================
# Cartella riassuntiva "colpo d'occhio": copia (rinominata) dei 6 dashboard
# per-backend/famiglia + 3 verdetti native-vs-prolog gia' generati sopra, in
# un'unica cartella piatta, cosi' non serve navigare i tre alberi per farsi
# un'idea complessiva. Sono COPIE (shutil.copy2): gli originali restano al
# loro posto nei rispettivi alberi graphs-*/.
# ===========================================================================
SUMMARY_DIR_NAME = "riassunto_grafici"

SUMMARY_SOURCES = [
    ("1_native_bsp", "graphs-native/1_BSP/_dashboard.png"),
    ("2_native_pup", "graphs-native/2_PUP/_dashboard.png"),
    ("3_native_hrp", "graphs-native/3_HRP/_dashboard.png"),
    ("4_prolog_bsp", "graphs-prolog/1_BSP/_dashboard.png"),
    ("5_prolog_pup", "graphs-prolog/2_PUP/_dashboard.png"),
    ("6_prolog_hrp", "graphs-prolog/3_HRP/_dashboard.png"),
    ("7_verdict_bsp", "graphs-comparison-native-prolog/1_BSP/_verdict.png"),
    ("8_verdict_pup", "graphs-comparison-native-prolog/2_PUP/_verdict.png"),
    ("9_verdict_hrp", "graphs-comparison-native-prolog/3_HRP/_verdict.png"),
]


def render_summary(base: Path) -> int:
    """Raccoglie i 6 dashboard per-backend/famiglia e i 3 verdetti
    native-vs-prolog gia' prodotti da render_backend_tree/render_comparison_tree
    in <base>/riassunto_grafici/, rinominati con un prefisso numerico cosi' da
    essere ordinabili e riconoscibili a colpo d'occhio dal solo nome file."""
    out_dir = base / SUMMARY_DIR_NAME
    out_dir.mkdir(parents=True, exist_ok=True)
    n = 0
    for dst_name, rel_src in SUMMARY_SOURCES:
        src = base / rel_src
        if not src.exists():
            print(f"  !! manca {src}, salto {dst_name}.png")
            continue
        shutil.copy2(src, out_dir / f"{dst_name}.png")
        n += 1
    return n


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
    print(f"Aggregato: {len(agg)} righe  backend={sorted(agg['backend'].unique())}  "
          f"famiglie={sorted(agg['family'].unique())}  machine={args.machine}")

    total = 0
    for backend in BACKENDS:
        if backend in set(agg["backend"].unique()):
            c = render_backend_tree(agg, backend, base, ground)
            print(f"  graphs-{backend}/: {c} PNG (varianti main: {', '.join(MAIN_VARIANTS)})")
            total += c
            e = render_exploratory_tree(agg, backend, base, ground)
            print(f"  graphs-{backend}/exploratory/: {e} PNG "
                  f"({', '.join(s['slug'] for s in EXPLORATORY_STUDIES)})")
            total += e
            for excl in VARIANT_EXCLUSIONS:
                variants = [v for v in MAIN_VARIANTS if v != excl["exclude"]]
                ce = render_backend_tree(agg, backend, base, ground,
                                         variants=variants,
                                         dir_suffix=f"-{excl['slug']}",
                                         label_suffix=f" — {excl['label']}")
                print(f"  graphs-{backend}/*-{excl['slug']}/: {ce} PNG "
                      f"(varianti: {', '.join(variants)})")
                total += ce
    c, verdicts = render_comparison_tree(agg, base)
    print(f"  graphs-comparison-native-prolog/: {c} PNG")
    total += c

    s = render_summary(base)
    print(f"  {SUMMARY_DIR_NAME}/: {s}/{len(SUMMARY_SOURCES)} file (copie rinominate dei dashboard/verdetti sopra)")

    if verdicts:
        print("\nVERDETTO native vs prolog (per area):")
        for fam, summ in verdicts.items():
            print(f"  {fam}: " + "  ".join(f"{a}={w}" for a, w in summ.items()))
    print(f"\nTotale PNG: {total}  (in {base}/)")


if __name__ == "__main__":
    main()
