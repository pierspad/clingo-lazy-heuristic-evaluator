"""
graphs.py
Generates benchmark charts for both BSP and PUP problems.

Reads CSV result files from ./test-results/ and generates charts
with mean ± standard deviation for each CDNL metric.

BSP results:  ./test-results/bsp_results.csv    → ./graphs/bsp/
PUP results:  ./test-results/pup_double_results.csv   → ./graphs/pup/
              ./test-results/pup_doublev_results.csv  → ./graphs/pup/

If a CSV file is missing, it is silently skipped.

Generated charts per problem:
    1. Main panel with all collected metrics (4x2)
    2. Single chart per metric
    3. Relative chart vs baseline variant

Each point is averaged across N seeds; the shaded band shows ±1σ.
"""

import argparse
import csv
import os
import sys
from collections import defaultdict

# ============================================================================
# Configuration
# ============================================================================

DEFAULT_RESULTS_DIR = "test-results"
DEFAULT_GRAPHS_DIR = "graphs"

METRIC_FIELDS = [
    "solving_s",
    "total_s",
    "choices",
    "conflicts",
    "restarts",
    "rules",
    "variables",
    "memory_mb",
]
INTEGER_METRICS = {"choices", "conflicts", "restarts", "rules", "variables"}

PLOT_CONFIGS = [
    {
        "metric": "solving_s",
        "title": "Solving Time (CDNL)",
        "ylabel": "Time (seconds)",
        "description": "Net time spent in CDNL search\n(grounding excluded)",
        "filename": "solving_time.png",
    },
    {
        "metric": "total_s",
        "title": "Total Time",
        "ylabel": "Time (seconds)",
        "description": "Grounding + Solving",
        "filename": "total_time.png",
    },
    {
        "metric": "choices",
        "title": "Choices (Decisions)",
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
        "metric": "rules",
        "title": "Ground Rules",
        "ylabel": "Number of rules",
        "description": "Size of the grounded program.\nLazy grounding should generate fewer rules",
        "filename": "rules_comparison.png",
    },
    {
        "metric": "variables",
        "title": "Propositional Variables",
        "ylabel": "Number of variables",
        "description": "Size of the propositional search space",
        "filename": "variables_comparison.png",
    },
    {
        "metric": "memory_mb",
        "title": "RSS Memory",
        "ylabel": "Memory (MB)",
        "description": "Peak resident memory usage",
        "filename": "memory_comparison.png",
    },
]

# ============================================================================
# Visual themes per problem type
# ============================================================================

BSP_THEME = {
    "variant_labels": {
        "std":  "Standard (__BSP.lp)",
        "lg":   "Lazy Grounding (_BSP_lg.lp)",
        "colg": "Lazy + Optimized Constraint (_BSP_colg.lp)",
    },
    "variant_colors": {
        "std":  "#E74C3C",   # red
        "lg":   "#2ECC71",   # green
        "colg": "#3498DB",   # blue
    },
    "variant_markers": {
        "std":  "o",
        "lg":   "s",
        "colg": "^",
    },
    "variant_order": ["std", "lg", "colg"],
    "xlabel": "Problem size (N)",
    "suptitle": "BSP Benchmark: Standard vs Lazy Heuristic Grounding",
    "baseline": "std",
}

# PUP: tutte e 4 le varianti usano clingo standard.
# Double/  → pup, pup_heur, pup_double
# DoubleVariant/ → pup_doublev
PUP_THEME = {
    "variant_labels": {
        "pup":        "Dichiarativo (__PUP.asp)",
        "pup_heur":   "Euristiche Statiche (__PUP_heur.asp)",
        "pup_double": "Aggregati Dinamici (__PUP_double.asp)",
        "pup_doublev":"Aggregati Dinamici Variante (__PUP_double_variant.asp)",
    },
    "variant_colors": {
        "pup":        "#E74C3C",   # red
        "pup_heur":   "#F39C12",   # orange
        "pup_double": "#2ECC71",   # green
        "pup_doublev":"#9B59B6",   # purple
    },
    "variant_markers": {
        "pup":        "o",
        "pup_heur":   "D",
        "pup_double": "s",
        "pup_doublev":"^",
    },
    "variant_order": ["pup", "pup_heur", "pup_double", "pup_doublev"],
    "xlabel": "Instance size (N)",
    "baseline": "pup",
}


# ============================================================================
# CSV loading with multi-seed support
# ============================================================================

def load_csv(csv_path: str):
    """
    Load CSV data and group values by (variant, n).
    Returns:
        {variant: {n: {metric: [values_per_seed]}}}
    """
    raw = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            variant = row["variant"].strip()
            n = int(row["n"])

            for metric in METRIC_FIELDS:
                val_str = row.get(metric, "").strip()
                if val_str not in ("NA", ""):
                    try:
                        raw[variant][n][metric].append(float(val_str))
                    except ValueError:
                        pass

    return raw


def compute_stats(raw):
    """
    Compute mean and standard deviation for each (variant, n, metric).
    Returns:
        {variant: {metric: {"n": [...], "mean": [...], "std": [...], "count": [...]}}}
    """
    import statistics

    result = {}
    for variant, n_data in raw.items():
        result[variant] = defaultdict(lambda: {"n": [], "mean": [], "std": [], "count": []})
        for n in sorted(n_data.keys()):
            for metric, values in n_data[n].items():
                if len(values) > 0:
                    mean_val = statistics.mean(values)
                    std_val = statistics.pstdev(values) if len(values) > 1 else 0.0
                    result[variant][metric]["n"].append(n)
                    result[variant][metric]["mean"].append(mean_val)
                    result[variant][metric]["std"].append(std_val)
                    result[variant][metric]["count"].append(len(values))

    return result


# ============================================================================
# Chart generation (parameterized by theme)
# ============================================================================

VARIANT_FILL_ALPHA = 0.15


def _ordered_variants(stats: dict, theme: dict):
    """Sort variants stably, keeping extra variants at the end."""
    order = theme["variant_order"]
    present = set(stats.keys())
    ordered = [v for v in order if v in present]
    ordered.extend(sorted(present - set(ordered)))
    return ordered


def generate_graphs(stats: dict, graphs_dir: str, theme: dict, title_suffix: str = ""):
    """Generate all charts for a given problem/theme."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import numpy as np
        from matplotlib.ticker import MaxNLocator
    except ImportError:
        print("Matplotlib is not installed. To enable plotting: pip install matplotlib numpy")
        sys.exit(1)

    os.makedirs(graphs_dir, exist_ok=True)

    labels = theme["variant_labels"]
    colors = theme["variant_colors"]
    markers = theme["variant_markers"]
    xlabel = theme["xlabel"]
    baseline = theme["baseline"]

    # Professional typography
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

    n_plots = len(PLOT_CONFIGS)
    n_cols = 2
    n_rows = (n_plots + n_cols - 1) // n_cols

    fig, axes = plt.subplots(n_rows, n_cols, figsize=(14, 4.4 * n_rows))
    axes_flat = axes.flatten()

    variants = _ordered_variants(stats, theme)

    for idx, config in enumerate(PLOT_CONFIGS):
        ax = axes_flat[idx]
        metric = config["metric"]
        has_data = False

        for variant in variants:
            if metric not in stats[variant]:
                continue

            data = stats[variant][metric]
            if not data["n"]:
                continue

            has_data = True
            n = np.array(data["n"])
            mean = np.array(data["mean"])
            std = np.array(data["std"])

            color = colors.get(variant, None)
            label = labels.get(variant, variant)
            marker = markers.get(variant, "o")

            ax.plot(n, mean, marker=marker, label=label, color=color,
                    linewidth=1.8, markersize=5, zorder=3)
            ax.fill_between(n, mean - std, mean + std,
                            alpha=VARIANT_FILL_ALPHA, color=color, zorder=2)

        ax.set_title(config["title"])
        ax.set_xlabel(xlabel)
        ax.set_ylabel(config["ylabel"])
        if has_data:
            ax.legend(loc="upper left")

        if metric in INTEGER_METRICS:
            ax.yaxis.set_major_locator(MaxNLocator(integer=True))

        ax.text(0.98, 0.02, config["description"],
                transform=ax.transAxes, fontsize=7, color="#666",
                ha="right", va="bottom", fontstyle="italic")

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
    plt.tight_layout(rect=[0, 0, 1, 0.96])

    suffix = f"_{title_suffix.lower().replace(' ', '_')}" if title_suffix else ""
    out_path = os.path.join(graphs_dir, f"benchmark_results{suffix}.png")
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Main chart saved to '{out_path}'.")

    # Export individual charts
    for cfg in PLOT_CONFIGS:
        name, ext = os.path.splitext(cfg["filename"])
        fname = f"{name}{suffix}{ext}" if title_suffix else cfg["filename"]
        _generate_single_chart(
            stats=stats,
            graphs_dir=graphs_dir,
            metric=cfg["metric"],
            title=cfg["title"],
            ylabel=cfg["ylabel"],
            filename=fname,
            theme=theme,
            xlabel=xlabel,
        )

    # Relative comparison chart
    rel_fname = f"comparison_vs_{baseline}{suffix}.png" if title_suffix else f"comparison_vs_{baseline}.png"
    _generate_relative_vs_baseline_chart(stats, graphs_dir, baseline, theme, rel_fname, xlabel)


def _generate_single_chart(stats, graphs_dir, metric, title, ylabel, filename, theme, xlabel):
    """Generate a single chart for one metric."""
    try:
        import matplotlib.pyplot as plt
        import numpy as np
        from matplotlib.ticker import MaxNLocator
    except ImportError:
        return

    labels = theme["variant_labels"]
    colors = theme["variant_colors"]
    markers_map = theme["variant_markers"]

    fig, ax = plt.subplots(figsize=(8, 5))
    variants = _ordered_variants(stats, theme)

    for variant in variants:
        if metric not in stats[variant]:
            continue
        data = stats[variant][metric]
        if not data["n"]:
            continue

        n = np.array(data["n"])
        mean = np.array(data["mean"])
        std = np.array(data["std"])

        color = colors.get(variant, None)
        label = labels.get(variant, variant)
        marker = markers_map.get(variant, "o")

        ax.plot(n, mean, marker=marker, label=label, color=color,
                linewidth=2, markersize=6, zorder=3)
        ax.fill_between(n, mean - std, mean + std,
                        alpha=VARIANT_FILL_ALPHA, color=color, zorder=2)

    ax.set_title(title, fontsize=13, fontweight="bold")
    ax.set_xlabel(xlabel, fontsize=11)
    ax.set_ylabel(ylabel, fontsize=11)
    ax.legend(fontsize=10)
    ax.grid(True, alpha=0.3, linestyle="--")
    if metric in INTEGER_METRICS:
        ax.yaxis.set_major_locator(MaxNLocator(integer=True))

    plt.tight_layout()
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Chart '{filename}' saved to '{out_path}'.")


def _generate_relative_vs_baseline_chart(stats, graphs_dir, baseline_variant, theme, filename, xlabel):
    """Generate a compact comparison chart relative to the baseline variant."""
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

    # 1) Speedup in total time
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

        color = colors.get(variant)
        marker = markers_map.get(variant, "o")
        label = labels.get(variant, variant)
        ax_speedup.plot(n_vals, speedup, marker=marker, linewidth=2,
                        color=color, label=label)

    ax_speedup.axhline(1.0, color="#555", linewidth=1, linestyle="--")
    ax_speedup.set_title(f"Total Time Speedup vs {labels.get(baseline_variant, baseline_variant)}")
    if has_positive_speedup:
        ax_speedup.set_yscale("log")
        ax_speedup.set_ylabel("Speedup (x, log scale)")
    else:
        ax_speedup.set_ylabel("Speedup (x)")
    ax_speedup.grid(True, alpha=0.3, linestyle="--")
    ax_speedup.legend(fontsize=9)

    # 2) Grounding reduction
    for variant in variants:
        color = colors.get(variant)
        marker = markers_map.get(variant, "o")
        pretty = labels.get(variant, variant)

        n_rules, base_rules, var_rules = _aligned_metric_pair(stats, baseline_variant, variant, "rules")
        if n_rules:
            red_rules = [100.0 * (b - v) / b if b != 0 else float("nan")
                         for b, v in zip(base_rules, var_rules)]
            ax_reduction.plot(n_rules, red_rules, marker=marker, linewidth=2,
                              color=color, linestyle="-", label=f"{pretty} - rules")

        n_vars, base_vars, var_vars = _aligned_metric_pair(stats, baseline_variant, variant, "variables")
        if n_vars:
            red_vars = [100.0 * (b - v) / b if b != 0 else float("nan")
                        for b, v in zip(base_vars, var_vars)]
            ax_reduction.plot(n_vars, red_vars, marker=marker, linewidth=2,
                              color=color, linestyle=":", label=f"{pretty} - variables")

    ax_reduction.axhline(0.0, color="#555", linewidth=1, linestyle="--")
    ax_reduction.set_title("Grounding Size Reduction vs Baseline")
    ax_reduction.set_xlabel(xlabel)
    ax_reduction.set_ylabel("Reduction (%)")
    ax_reduction.grid(True, alpha=0.3, linestyle="--")
    ax_reduction.legend(fontsize=8, ncol=2)

    plt.tight_layout()
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Chart '{filename}' saved to '{out_path}'.")


def _aligned_metric_pair(stats, baseline_variant, variant, metric):
    """Return aligned (N, baseline_mean, variant_mean) lists for one metric."""
    if metric not in stats.get(baseline_variant, {}) or metric not in stats.get(variant, {}):
        return [], [], []

    base_data = stats[baseline_variant][metric]
    var_data = stats[variant][metric]

    base_map = dict(zip(base_data["n"], base_data["mean"]))
    var_map = dict(zip(var_data["n"], var_data["mean"]))

    common_n = sorted(set(base_map.keys()) & set(var_map.keys()))
    return common_n, [base_map[n] for n in common_n], [var_map[n] for n in common_n]


def _detect_seeds(stats):
    """Detect seed count from aggregated metric counts."""
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
    """Return estimated number of seeds per variant."""
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


# ============================================================================
# Summary table
# ============================================================================

def print_summary_table(stats, theme):
    """Print a summary table with means for key metrics."""
    variants = _ordered_variants(stats, theme)
    labels = theme["variant_labels"]
    table_width = 8 + len(variants) * 56

    print(f"\n{'='*table_width}")
    print(f"{'N':>5}  ", end="")
    for v in variants:
        label = labels.get(v, v)
        print(f"  {label:>35}", end="")
    print()
    print(f"{'':>5}  ", end="")
    for _ in variants:
        print(f"  {'Solv(s)':>8} {'Tot(s)':>8} {'Choices':>8} {'Conf.':>8} {'Rst.':>6} {'Rules':>7} {'Vars':>7}", end="")
    print()
    print("-" * table_width)

    all_ns = set()
    for v in variants:
        for metric_data in stats[v].values():
            all_ns.update(metric_data["n"])

    for n in sorted(all_ns):
        row = f"{n:>5}  "
        for v in variants:
            solving = _get_mean_at_n(stats[v], "solving_s", n)
            total = _get_mean_at_n(stats[v], "total_s", n)
            choices = _get_mean_at_n(stats[v], "choices", n)
            conflicts = _get_mean_at_n(stats[v], "conflicts", n)
            restarts = _get_mean_at_n(stats[v], "restarts", n)
            rules = _get_mean_at_n(stats[v], "rules", n)
            variables = _get_mean_at_n(stats[v], "variables", n)

            s_str = f"{solving:.4f}" if solving is not None else "N/A"
            t_str = f"{total:.4f}" if total is not None else "N/A"
            c_str = f"{choices:.0f}" if choices is not None else "N/A"
            f_str = f"{conflicts:.0f}" if conflicts is not None else "N/A"
            rs_str = f"{restarts:.0f}" if restarts is not None else "N/A"
            r_str = f"{rules:.0f}" if rules is not None else "N/A"
            v_str = f"{variables:.0f}" if variables is not None else "N/A"

            row += f"  {s_str:>8} {t_str:>8} {c_str:>8} {f_str:>8} {rs_str:>6} {r_str:>7} {v_str:>7}"
        print(row)

    print(f"{'='*table_width}\n")


def _get_mean_at_n(variant_stats, metric, n):
    """Return mean for a given N, or None if unavailable."""
    if metric not in variant_stats:
        return None
    data = variant_stats[metric]
    if n in data["n"]:
        idx = data["n"].index(n)
        return data["mean"][idx]
    return None


# ============================================================================
# Processing pipeline
# ============================================================================

def process_csv(csv_path, graphs_dir, theme, problem_name, title_suffix=""):
    """Process a single CSV file: load, compute stats, print table, generate graphs."""
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
    print_summary_table(stats, theme)
    generate_graphs(stats, graphs_dir, theme, title_suffix=title_suffix)
    return True


# ============================================================================
# Main
# ============================================================================

def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate charts from BSP and PUP benchmark results."
    )
    parser.add_argument("--results-dir", default=DEFAULT_RESULTS_DIR,
                        help=f"Directory with result CSV files (default: {DEFAULT_RESULTS_DIR})")
    parser.add_argument("--out", default=DEFAULT_GRAPHS_DIR,
                        help=f"Base output directory for charts (default: {DEFAULT_GRAPHS_DIR})")
    return parser.parse_args()


def main():
    args = parse_args()
    results_dir = args.results_dir
    base_out = args.out

    processed_any = False

    # ---- BSP ----
    bsp_csv = os.path.join(results_dir, "bsp_results.csv")
    bsp_out = os.path.join(base_out, "bsp")
    bsp_theme = BSP_THEME.copy()
    bsp_theme["suptitle"] = "BSP Benchmark: Standard vs Lazy Heuristic Grounding"
    if process_csv(bsp_csv, bsp_out, bsp_theme, "BSP (Balanced Sum Partition)"):
        processed_any = True

    # ---- PUP Double ----
    pup_double_csv = os.path.join(results_dir, "pup_double_results.csv")
    pup_double_out = os.path.join(base_out, "pup")
    pup_double_theme = PUP_THEME.copy()
    pup_double_theme["suptitle"] = "PUP Benchmark — Double Family"
    if process_csv(pup_double_csv, pup_double_out, pup_double_theme,
                   "PUP Double", title_suffix="Double"):
        processed_any = True

    # ---- PUP DoubleV ----
    pup_doublev_csv = os.path.join(results_dir, "pup_doublev_results.csv")
    pup_doublev_out = os.path.join(base_out, "pup")
    pup_doublev_theme = PUP_THEME.copy()
    pup_doublev_theme["suptitle"] = "PUP Benchmark — DoubleV Family"
    if process_csv(pup_doublev_csv, pup_doublev_out, pup_doublev_theme,
                   "PUP DoubleV", title_suffix="DoubleV"):
        processed_any = True

    # ---- Legacy BSP CSV (backward compat) ----
    legacy_csv = os.path.join(results_dir, "results.csv")
    if not processed_any and os.path.isfile(legacy_csv):
        print(f"\n[FALLBACK] Trovato file legacy '{legacy_csv}', lo processo come BSP...")
        legacy_out = os.path.join(base_out, "bsp")
        process_csv(legacy_csv, legacy_out, BSP_THEME,
                    "BSP (Legacy)", title_suffix="legacy")
        processed_any = True

    if not processed_any:
        print("\nNessun file CSV di risultati trovato.")
        print("Esegui prima benchmark_bsp.sh e/o benchmark_pup.sh.")
        sys.exit(1)

    print(f"\nDone. Tutti i grafici sono in '{base_out}/'.")


if __name__ == "__main__":
    main()
