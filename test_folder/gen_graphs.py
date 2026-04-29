"""
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
import shutil
import sys
import textwrap
from collections import defaultdict

# ============================================================================
# Configuration
# ============================================================================

DEFAULT_RESULTS_DIR = "test-results"
DEFAULT_GRAPHS_DIR = "graphs"

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
    "ground_heuristics",
    "ground_lazy_heuristic_facts",
    "ground_facts",
    "ground_lines",
]
INTEGER_METRICS = {
    "choices",
    "conflicts",
    "restarts",
    "rules",
    "variables",
    "ground_heuristics",
    "ground_lazy_heuristic_facts",
    "combined_heuristics",
    "ground_facts",
    "ground_lines",
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
}

PLOT_CONFIGS = [
    {
        "metric": "grounding_s",
        "title": "Grounding Time",
        "ylabel": "Time (seconds)",
        "description": "Time before CDNL search. For old CSV files this is derived as total time minus solving time.",
        "filename": "grounding_time.png",
    },
    {
        "metric": "solving_s",
        "title": "Solving Time (CDNL)",
        "ylabel": "Time (seconds)",
        "description": "Net time spent in CDNL search\n(grounding excluded)",
        "filename": "solving_time.png",
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
        "metric": "ground_lines",
        "title": "Ground Program Lines",
        "ylabel": "Lines in --text output",
        "description": "Line count of the textual ground program, comparable to clingo/gringo --text | wc -l.",
        "filename": "ground_program_lines.png",
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
    {
        "metric": "combined_heuristics",
        "title": "Heuristics Grounding",
        "ylabel": "Ground heuristic entries",
        "description": "Standard: native #heuristic directives\nLazy: __heuristic facts passed to the propagator",
        "filename": "combined_heuristics.png",
    },
    {
        "metric": "ground_facts",
        "title": "Ground Facts",
        "ylabel": "Ground facts",
        "description": "Facts in --text output, including __heuristic facts",
        "filename": "ground_facts.png",
    },
]

# ============================================================================
# Visual themes per problem type
# ============================================================================

BSP_THEME = {
    "variant_labels": {
        "std":  "Standard (BSP.lp)",
        "std_aux": "Standard + Aux (BSP_aux.lp)",
        "asgs": "Alpha Ground+Solve (BSP_asgs.lp)",
        "lg":   "Lazy Grounding (BSP_lg.lp)",
        "cslg": "Lazy + Clingo Semantics (BSP_cslg.lp)",
        "auxlg": "Lazy + Aux (BSP_auxlg.lp)",
        "colg": "Lazy + Optimized Constraint (BSP_colg.lp)",
    },
    "variant_colors": {
        "std":  "#E74C3C",   # red
        "std_aux": "#C0392B", # dark red
        "asgs": "#F39C12",   # orange
        "lg":   "#2ECC71",   # green
        "cslg": "#9B59B6",   # purple
        "auxlg": "#16A085",  # teal
        "colg": "#3498DB",   # blue
    },
    "variant_markers": {
        "std":  "o",
        "std_aux": "X",
        "asgs": "v",
        "lg":   "s",
        "cslg": "D",
        "auxlg": "P",
        "colg": "^",
    },
    "variant_order": ["std", "std_aux", "asgs", "lg", "cslg", "auxlg", "colg"],
    "xlabel": "Problem size (N)",
    "suptitle": "BSP Benchmark: Standard vs Lazy Heuristic Grounding",
    "baseline": "std",
}

# PUP: benchmark con binario clingo modificato.
# Double/  → pup, pup_heur, pup_double
# DoubleVariant/ → pup, pup_heur, pup_doublev
PUP_THEME = {
    "variant_labels": {
        "pup":        "Dichiarativo (PUP.lp)",
        "pup_heur":   "Euristiche Statiche (PUP_heur.lp)",
        "pup_double_std": "PUP Double #heuristic",
        "pup_double_aux": "PUP Double #heuristic + Aux",
        "pup_double": "Aggregati Dinamici (PUP_double_lg.lp)",
        "pup_double_aux_lg": "Aggregati Dinamici + Aux",
        "pup_doublev_std": "PUP DoubleV #heuristic",
        "pup_doublev_aux": "PUP DoubleV #heuristic + Aux",
        "pup_doublev":"Aggregati Dinamici Variante (PUP_double_variant_lg.lp)",
        "pup_doublev_aux_lg": "Aggregati Dinamici Variante + Aux",
    },
    "variant_colors": {
        "pup":        "#E74C3C",   # red
        "pup_heur":   "#F39C12",   # orange
        "pup_double_std": "#8E44AD", # purple
        "pup_double_aux": "#6C3483", # dark purple
        "pup_double": "#2ECC71",   # green
        "pup_double_aux_lg": "#16A085", # teal
        "pup_doublev_std": "#8E44AD",
        "pup_doublev_aux": "#6C3483",
        "pup_doublev":"#9B59B6",   # purple
        "pup_doublev_aux_lg": "#16A085",
    },
    "variant_markers": {
        "pup":        "o",
        "pup_heur":   "D",
        "pup_double_std": "X",
        "pup_double_aux": "P",
        "pup_double": "s",
        "pup_double_aux_lg": "*",
        "pup_doublev_std": "X",
        "pup_doublev_aux": "P",
        "pup_doublev":"^",
        "pup_doublev_aux_lg": "*",
    },
    "variant_order": [
        "pup",
        "pup_heur",
        "pup_double_std",
        "pup_double_aux",
        "pup_double",
        "pup_double_aux_lg",
        "pup_doublev_std",
        "pup_doublev_aux",
        "pup_doublev",
        "pup_doublev_aux_lg",
    ],
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
            row_values = {}

            for metric in METRIC_FIELDS:
                val_str = row.get(metric, "").strip()
                if val_str not in ("NA", ""):
                    try:
                        value = float(val_str)
                        row_values[metric] = value
                    except ValueError:
                        pass

            legacy_failed_run = _looks_like_legacy_failed_lazy_run(row_values)
            invalid_on_failure = {
                "grounding_s",
                "solving_s",
                "total_s",
                "choices",
                "conflicts",
                "restarts",
                "rules",
                "variables",
                "memory_mb",
            }

            for metric, value in row_values.items():
                if legacy_failed_run and metric in invalid_on_failure:
                    continue
                raw[variant][n][metric].append(value)

            heuristic_values = [
                row_values[m]
                for m in ("ground_heuristics", "ground_lazy_heuristic_facts")
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
    """
    Older benchmark scripts ignored clingo's non-zero exit status.
    Lazy runs that failed in propagator initialization were consequently stored
    as zero-rule/zero-choice data points; treat that signature as missing data.
    """
    return (
        row_values.get("ground_lazy_heuristic_facts", 0.0) > 0.0 and
        row_values.get("rules") == 0.0 and
        row_values.get("choices") == 0.0 and
        row_values.get("conflicts") == 0.0 and
        row_values.get("solving_s") == 0.0 and
        row_values.get("variables", 0.0) > 0.0
    )


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
CAPTION_COLOR = "#5F6368"
SEPARATOR_COLOR = "#D6D6D6"
VERTICAL_SEPARATOR_GAP_FRACTION = 0.42
MILLION_FORMAT_METRICS = {
    "variables",
    "combined_heuristics",
    "ground_lines",
}


def _add_axis_caption(ax, description: str, *, y: float, width: int, fontsize: int):
    """Place the metric description below the plot area as a caption."""
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


def _format_compact_number(value, _pos=None):
    """Format large axis ticks without scientific-offset notation."""
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
    """Format grounding-size ticks in millions, keeping sub-million values as decimals."""
    abs_value = abs(value)
    if abs_value >= 100_000:
        scaled = value / 1_000_000
        return f"{scaled:.1f}".rstrip("0").rstrip(".") + "M"
    if abs_value >= 1:
        return f"{value:.0f}"
    if value == 0:
        return "0"
    return f"{value:g}"


def _format_memory_mb(value, _pos=None):
    """Format MB ticks compactly while keeping the axis unit in the label."""
    abs_value = abs(value)
    if abs_value >= 1_000:
        scaled = value / 1_000
        return f"{scaled:.1f}".rstrip("0").rstrip(".") + "k"
    if abs_value >= 1:
        return f"{value:.0f}"
    if value == 0:
        return "0"
    return f"{value:g}"


def _apply_y_axis_format(ax, metric: str):
    """Keep count-like axes readable and consistent across charts."""
    from matplotlib.ticker import FuncFormatter, MaxNLocator

    if metric == "memory_mb":
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6))
        ax.yaxis.set_major_formatter(FuncFormatter(_format_memory_mb))
    elif metric in MILLION_FORMAT_METRICS:
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6, integer=True))
        ax.yaxis.set_major_formatter(FuncFormatter(_format_millions))
    elif metric in INTEGER_METRICS:
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6, integer=True))
        ax.yaxis.set_major_formatter(FuncFormatter(_format_compact_number))
    else:
        return

    ax.yaxis.offsetText.set_visible(False)


def _add_subplot_separators(fig, axes, n_plots: int):
    """Draw thin separators between subplot cells in the combined chart."""
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
    """Append an interpretation hint only to metrics where lower values are better."""
    if metric in LOWER_IS_BETTER_METRICS:
        return f"{title}\n(Lower is better)"
    return title


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

    fig, axes = plt.subplots(n_rows, n_cols, figsize=(14, 4.8 * n_rows))
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

        ax.set_title(_format_title(metric, config["title"]))
        ax.set_xlabel(xlabel)
        ax.set_ylabel(config["ylabel"])
        if has_data:
            ax.legend(loc="upper left")

        _apply_y_axis_format(ax, metric)

        _add_axis_caption(ax, config["description"], y=-0.27, width=64, fontsize=7)

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
            title=_format_title(cfg["metric"], cfg["title"]),
            ylabel=cfg["ylabel"],
            description=cfg["description"],
            filename=fname,
            theme=theme,
            xlabel=xlabel,
        )

    # Relative comparison chart
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


def _generate_single_chart(stats, graphs_dir, metric, title, ylabel, description, filename, theme, xlabel):
    """Generate a single chart for one metric."""
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
        marker = markers_map.get(variant, "o")

        ax.plot(n, mean, marker=marker, label=label, color=color,
                linewidth=2, markersize=6, zorder=3)
        ax.fill_between(n, mean - std, mean + std,
                        alpha=VARIANT_FILL_ALPHA, color=color, zorder=2)

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

    _add_axis_caption(ax, description, y=-0.20, width=88, fontsize=8)

    plt.tight_layout(rect=[0, 0.05, 1, 1])
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

        size_metric = _preferred_ground_size_metric(stats, baseline_variant, variant)
        n_size, base_size, var_size = _aligned_metric_pair(stats, baseline_variant, variant, size_metric)
        if n_size:
            red_size = [100.0 * (b - v) / b if b != 0 else float("nan")
                        for b, v in zip(base_size, var_size)]
            size_label = "ground lines" if size_metric == "ground_lines" else "solver rules"
            ax_reduction.plot(n_size, red_size, marker=marker, linewidth=2,
                              color=color, linestyle="-", label=f"{pretty} - {size_label}")

        n_vars, base_vars, var_vars = _aligned_metric_pair(stats, baseline_variant, variant, "variables")
        if n_vars:
            red_vars = [100.0 * (b - v) / b if b != 0 else float("nan")
                        for b, v in zip(base_vars, var_vars)]
            ax_reduction.plot(n_vars, red_vars, marker=marker, linewidth=2,
                              color=color, linestyle=":", label=f"{pretty} - variables")

    ax_reduction.axhline(0.0, color="#555", linewidth=1, linestyle="--")
    ax_reduction.set_title("Ground Program Size Reduction vs Baseline")
    ax_reduction.set_xlabel(xlabel)
    ax_reduction.set_ylabel("Reduction (%)")
    ax_reduction.grid(True, alpha=0.3, linestyle="--")
    ax_reduction.legend(fontsize=8, ncol=2)

    plt.tight_layout()
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Chart '{filename}' saved to '{out_path}'.")


def _metric_mean_map(stats, variant, metric):
    """Return {N: mean} for a metric, or an empty map."""
    if metric not in stats.get(variant, {}):
        return {}
    data = stats[variant][metric]
    return dict(zip(data["n"], data["mean"]))


def _effective_heuristic_map(stats, variant):
    """
    Return the heuristic grounding size for each N.
    Native encodings use ground_heuristics; lazy encodings use
    ground_lazy_heuristic_facts. If both exist, use their sum.
    """
    native = _metric_mean_map(stats, variant, "ground_heuristics")
    lazy = _metric_mean_map(stats, variant, "ground_lazy_heuristic_facts")
    ns = sorted(set(native.keys()) | set(lazy.keys()))
    return {n: native.get(n, 0.0) + lazy.get(n, 0.0) for n in ns}


def _generate_heuristics_vs_facts_chart(stats, graphs_dir, theme, filename, xlabel):
    """Plot native #heuristic and lazy __heuristic facts against all other facts."""
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        return

    labels = theme["variant_labels"]
    colors = theme["variant_colors"]
    markers_map = theme["variant_markers"]

    fig, ax = plt.subplots(figsize=(9, 5.4))
    has_data = False

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
            ax.plot(common_n, native_ratio, marker=marker, linewidth=2,
                    color=color, linestyle="-", label=f"{pretty} - #heuristic/other facts")
        if any(v == v and v > 0 for v in lazy_ratio):
            has_data = True
            ax.plot(common_n, lazy_ratio, marker=marker, linewidth=2,
                    color=color, linestyle=":", label=f"{pretty} - __heuristic facts/other facts")

    ax.set_title("Heuristic Grounding Weight vs Other Facts", fontsize=13, fontweight="bold")
    ax.set_xlabel(xlabel, fontsize=11)
    ax.set_ylabel("Ratio (%)")
    ax.grid(True, alpha=0.3, linestyle="--")
    if has_data:
        ax.set_yscale("log")
        ax.legend(fontsize=8, ncol=1)
    else:
        ax.text(0.5, 0.5, "No heuristic/fact data", transform=ax.transAxes,
                ha="center", va="center", fontsize=13, color="#AAA")

    plt.tight_layout()
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"  Chart '{filename}' saved to '{out_path}'.")


def _generate_heuristic_reduction_chart(stats, graphs_dir, baseline_variant, theme, filename, xlabel):
    """Plot the reduction in heuristic grounding against the baseline variant."""
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
        ax.plot(common_n, reduction,
                marker=markers_map.get(variant, "o"),
                linewidth=2,
                color=colors.get(variant),
                label=labels.get(variant, variant))

    ax.axhline(0.0, color="#555", linewidth=1, linestyle="--")
    ax.set_title(f"Heuristic Grounding Reduction vs {labels.get(baseline_variant, baseline_variant)}",
                 fontsize=13, fontweight="bold")
    ax.set_xlabel(xlabel, fontsize=11)
    ax.set_ylabel("Reduction (%)")
    ax.grid(True, alpha=0.3, linestyle="--")
    if has_data:
        ax.legend(fontsize=9)
    else:
        ax.text(0.5, 0.5, "No comparable heuristic counts", transform=ax.transAxes,
                ha="center", va="center", fontsize=13, color="#AAA")

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


def _preferred_ground_size_metric(stats, baseline_variant, variant):
    """Use textual ground-program lines when available; otherwise fall back to clingo's Rules statistic."""
    if (
        "ground_lines" in stats.get(baseline_variant, {}) and
        "ground_lines" in stats.get(variant, {})
    ):
        return "ground_lines"
    return "rules"


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
    table_width = 8 + len(variants) * 78

    print(f"\n{'='*table_width}")
    print(f"{'N':>5}  ", end="")
    for v in variants:
        label = labels.get(v, v)
        print(f"  {label:>35}", end="")
    print()
    print(f"{'':>5}  ", end="")
    for _ in variants:
        print(f"  {'Grnd(s)':>8} {'Solv(s)':>8} {'Tot(s)':>8} {'Choices':>8} {'Conf.':>8} {'Rst.':>6} {'Lines':>7} {'Rules':>7} {'Vars':>7} {'Heur':>7} {'LazyH':>7} {'Facts':>7}", end="")
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
            gl_str = f"{ground_lines:.0f}" if ground_lines is not None else "N/A"
            r_str = f"{rules:.0f}" if rules is not None else "N/A"
            v_str = f"{variables:.0f}" if variables is not None else "N/A"
            h_str = f"{ground_heuristics:.0f}" if ground_heuristics is not None else "N/A"
            lh_str = f"{ground_lazy:.0f}" if ground_lazy is not None else "N/A"
            gf_str = f"{ground_facts:.0f}" if ground_facts is not None else "N/A"

            row += f"  {g_str:>8} {s_str:>8} {t_str:>8} {c_str:>8} {f_str:>8} {rs_str:>6} {gl_str:>7} {r_str:>7} {v_str:>7} {h_str:>7} {lh_str:>7} {gf_str:>7}"
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

def reset_graphs_dir(graphs_dir):
    """Remove previous generated charts before rebuilding them from CSV data."""
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
    """Fail before touching graph outputs if plotting dependencies are missing."""
    try:
        import matplotlib  # noqa: F401
        import numpy  # noqa: F401
    except ImportError:
        print("Matplotlib/Numpy non sono installati.")
        print("Crea un virtualenv e installa le dipendenze, ad esempio:")
        print("  python3 -m venv /tmp/clingo-graphs-venv")
        print("  /tmp/clingo-graphs-venv/bin/python -m pip install -r test_folder/requirements.txt")
        print("  cd test_folder && /tmp/clingo-graphs-venv/bin/python gen_graphs.py")
        sys.exit(1)


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

    expected_csvs = [
        os.path.join(results_dir, "bsp_results.csv"),
        os.path.join(results_dir, "pup_double_results.csv"),
        os.path.join(results_dir, "pup_doublev_results.csv"),
        os.path.join(results_dir, "results.csv"),
    ]
    if any(os.path.isfile(path) for path in expected_csvs):
        ensure_plot_dependencies()
        reset_graphs_dir(base_out)

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
    pup_double_theme["heuristic_baseline"] = "pup_double_std"
    if process_csv(pup_double_csv, pup_double_out, pup_double_theme,
                   "PUP Double", title_suffix="Double"):
        processed_any = True

    # ---- PUP DoubleV ----
    pup_doublev_csv = os.path.join(results_dir, "pup_doublev_results.csv")
    pup_doublev_out = os.path.join(base_out, "pup")
    pup_doublev_theme = PUP_THEME.copy()
    pup_doublev_theme["suptitle"] = "PUP Benchmark — DoubleV Family"
    pup_doublev_theme["heuristic_baseline"] = "pup_doublev_std"
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
