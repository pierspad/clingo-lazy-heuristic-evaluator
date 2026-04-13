"""
graphs.py
Reads multi-seed results from ./test-results/results.csv and generates charts
with mean ± standard deviation for each CDNL metric.

Generated charts:
    1. Main panel with all collected metrics (4x2):
       - Solving Time
       - Total Time
       - Choices
       - Conflicts
       - Restarts
       - Rules
       - Variables
       - RSS Memory
    2. Single chart per metric (8 files total)
    3. Relative chart vs baseline variant (default: std)

Legacy list (original 3x2 panel):
    1. Solving Time (net CDNL)
    2. Total Time (grounding + solving)
    3. Choices (solver decisions)
    4. Conflicts (conflicts / backtracking)
    5. Rules (grounding size)
    6. RSS Memory

Each point is averaged across N seeds; the shaded band shows ±1σ.
"""

import argparse
import csv
import os
import sys
from collections import defaultdict

DEFAULT_CSV = os.path.join("test-results", "results.csv")
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
# Visual configuration
# ============================================================================

VARIANT_LABELS = {
    "std": "Clingo Standard",
    "mod": "Clingo Lazy (Modified)",
    "mod_opt": "Clingo Lazy (Optimized Constraint)",
}
VARIANT_COLORS = {
    "std": "#E74C3C",   # elegant red
    "mod": "#2ECC71",   # elegant green
    "mod_opt": "#3498DB",  # elegant blue
}
VARIANT_FILL_ALPHA = 0.15
VARIANT_MARKERS = {
    "std": "o",
    "mod": "s",
    "mod_opt": "^",
}
VARIANT_ORDER = ["std", "mod", "mod_opt"]


def _ordered_variants(stats: dict):
    """Sort variants stably, keeping extra variants at the end."""
    present = set(stats.keys())
    ordered = [v for v in VARIANT_ORDER if v in present]
    ordered.extend(sorted(present - set(ordered)))
    return ordered

# Definition of the charts for the main panel and single exports
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
# Chart generation
# ============================================================================

def generate_graphs(stats: dict, graphs_dir: str, baseline_variant: str = "std"):
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
    axes = axes.flatten()

    variants = _ordered_variants(stats)

    for idx, config in enumerate(PLOT_CONFIGS):
        ax = axes[idx]
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

            color = VARIANT_COLORS.get(variant, None)
            label = VARIANT_LABELS.get(variant, variant)
            marker = VARIANT_MARKERS.get(variant, "o")

            ax.plot(n, mean, marker=marker, label=label, color=color,
                    linewidth=1.8, markersize=5, zorder=3)

            # Shaded band ±1σ
            ax.fill_between(n, mean - std, mean + std,
                            alpha=VARIANT_FILL_ALPHA, color=color, zorder=2)

        ax.set_title(config["title"])
        ax.set_xlabel("Problem size (N)")
        ax.set_ylabel(config["ylabel"])
        if has_data:
            ax.legend(loc="upper left")

        # Count-based metrics should use integer ticks.
        if metric in INTEGER_METRICS:
            ax.yaxis.set_major_locator(MaxNLocator(integer=True))

        # Descriptive annotation
        ax.text(0.98, 0.02, config["description"],
                transform=ax.transAxes, fontsize=7, color="#666",
                ha="right", va="bottom",
                fontstyle="italic")

        if not has_data:
            ax.text(0.5, 0.5, "No data", transform=ax.transAxes,
                    ha="center", va="center", fontsize=14, color="#CCC")

    # Hide any trailing empty axes if the grid is larger than the number of plots.
    for ax in axes[n_plots:]:
        ax.axis("off")

    fig.suptitle("BSP Benchmark: Standard and Lazy Heuristic Grounding Variants\n"
                 f"(mean ± σ over {_detect_seeds(stats)} seeds per point)",
                 fontsize=14, fontweight="bold", y=0.98)

    plt.tight_layout(rect=[0, 0, 1, 0.96])

    out_path = os.path.join(graphs_dir, "benchmark_results.png")
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"Main chart saved to '{out_path}'.")

    # Export one single chart for each metric.
    for cfg in PLOT_CONFIGS:
        _generate_single_chart(
            stats=stats,
            graphs_dir=graphs_dir,
            metric=cfg["metric"],
            title=cfg["title"],
            ylabel=cfg["ylabel"],
            filename=cfg["filename"],
        )

    _generate_relative_vs_baseline_chart(stats, graphs_dir, baseline_variant)


def _generate_single_chart(stats, graphs_dir, metric, title, ylabel, filename):
    """Generate a single chart for one metric (useful for thesis figures)."""
    try:
        import matplotlib.pyplot as plt
        import numpy as np
        from matplotlib.ticker import MaxNLocator
    except ImportError:
        return

    fig, ax = plt.subplots(figsize=(8, 5))
    variants = _ordered_variants(stats)

    for variant in variants:
        if metric not in stats[variant]:
            continue
        data = stats[variant][metric]
        if not data["n"]:
            continue

        n = np.array(data["n"])
        mean = np.array(data["mean"])
        std = np.array(data["std"])

        color = VARIANT_COLORS.get(variant, None)
        label = VARIANT_LABELS.get(variant, variant)
        marker = VARIANT_MARKERS.get(variant, "o")

        ax.plot(n, mean, marker=marker, label=label, color=color,
                linewidth=2, markersize=6, zorder=3)
        ax.fill_between(n, mean - std, mean + std,
                        alpha=VARIANT_FILL_ALPHA, color=color, zorder=2)

    ax.set_title(title, fontsize=13, fontweight="bold")
    ax.set_xlabel("Problem size (N)", fontsize=11)
    ax.set_ylabel(ylabel, fontsize=11)
    ax.legend(fontsize=10)
    ax.grid(True, alpha=0.3, linestyle="--")
    if metric in INTEGER_METRICS:
        ax.yaxis.set_major_locator(MaxNLocator(integer=True))

    plt.tight_layout()
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"Chart '{filename}' saved to '{out_path}'.")


def _generate_relative_vs_baseline_chart(stats, graphs_dir, baseline_variant="std"):
    """Generate a compact comparison chart relative to the baseline variant."""
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return

    if baseline_variant not in stats:
        print(f"Relative chart skipped: baseline '{baseline_variant}' not found.")
        return

    variants = [v for v in _ordered_variants(stats) if v != baseline_variant]
    if not variants:
        print("Relative chart skipped: no non-baseline variants available.")
        return

    fig, axes = plt.subplots(2, 1, figsize=(9, 8), sharex=True)
    ax_speedup, ax_reduction = axes
    has_positive_speedup = False

    # 1) Speedup in total time: baseline_time / variant_time.
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

        color = VARIANT_COLORS.get(variant)
        marker = VARIANT_MARKERS.get(variant, "o")
        label = VARIANT_LABELS.get(variant, variant)
        ax_speedup.plot(n_vals, speedup, marker=marker, linewidth=2,
                        color=color, label=label)

    ax_speedup.axhline(1.0, color="#555", linewidth=1, linestyle="--")
    ax_speedup.set_title(f"Total Time Speedup vs {VARIANT_LABELS.get(baseline_variant, baseline_variant)}")
    if has_positive_speedup:
        ax_speedup.set_yscale("log")
        ax_speedup.set_ylabel("Speedup (x, log scale)")
    else:
        ax_speedup.set_ylabel("Speedup (x)")
    ax_speedup.grid(True, alpha=0.3, linestyle="--")
    ax_speedup.legend(fontsize=9)

    # 2) Grounding reduction percentages for rules and variables.
    for variant in variants:
        color = VARIANT_COLORS.get(variant)
        marker = VARIANT_MARKERS.get(variant, "o")
        pretty = VARIANT_LABELS.get(variant, variant)

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
    ax_reduction.set_xlabel("Problem size (N)")
    ax_reduction.set_ylabel("Reduction (%)")
    ax_reduction.grid(True, alpha=0.3, linestyle="--")
    ax_reduction.legend(fontsize=8, ncol=2)

    plt.tight_layout()
    out_path = os.path.join(graphs_dir, f"comparison_vs_{baseline_variant}.png")
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"Chart 'comparison_vs_{baseline_variant}.png' saved to '{out_path}'.")


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
    """Return estimated number of seeds per variant, using solving_s when possible."""
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

def print_summary_table(stats):
    """Print a summary table with means for key metrics."""
    variants = _ordered_variants(stats)
    table_width = 8 + len(variants) * 56

    print(f"\n{'='*table_width}")
    print(f"{'N':>5}  ", end="")
    for v in variants:
        label = VARIANT_LABELS.get(v, v)
        print(f"  {label:>35}", end="")
    print()
    print(f"{'':>5}  ", end="")
    for _ in variants:
        print(f"  {'Solv(s)':>8} {'Tot(s)':>8} {'Choices':>8} {'Conf.':>8} {'Rst.':>6} {'Rules':>7} {'Vars':>7}", end="")
    print()
    print("-" * table_width)

    # Collect all N values
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
# Main
# ============================================================================

def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate charts from benchmark results with CDNL statistics (multi-seed CSV)."
    )
    parser.add_argument("--csv", default=DEFAULT_CSV,
                        help=f"Path to the benchmark CSV file (default: {DEFAULT_CSV})")
    parser.add_argument("--out", default=DEFAULT_GRAPHS_DIR,
                        help=f"Output directory for charts (default: {DEFAULT_GRAPHS_DIR})")
    parser.add_argument("--baseline", default="std",
                        help="Baseline variant for relative comparison chart (default: std)")
    return parser.parse_args()


def main():
    args = parse_args()

    if not os.path.isfile(args.csv):
        print(f"Error: CSV file not found: '{args.csv}'")
        print("Run benchmark.sh first to collect data.")
        sys.exit(1)

    print(f"Loading results from '{args.csv}'...")
    raw = load_csv(args.csv)

    if not raw:
        print("Error: CSV is empty or contains no valid data.")
        sys.exit(1)

    print(f"Found variants: {list(raw.keys())}")
    seeds_per_variant = _detect_seeds_per_variant(raw)
    for variant, n_data in raw.items():
        ns = sorted(n_data.keys())
        seeds = seeds_per_variant.get(variant, "0")
        print(f"  {variant}: {len(ns)} N values, ~{seeds} seeds per point")

    stats = compute_stats(raw)

    print_summary_table(stats)
    generate_graphs(stats, args.out, baseline_variant=args.baseline)


if __name__ == "__main__":
    main()
