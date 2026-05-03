


import argparse
import csv
import os
import shutil
import sys
import textwrap
from collections import defaultdict


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TEST_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_RESULTS_DIR = os.path.join(TEST_ROOT, "results")
DEFAULT_GRAPHS_DIR = os.path.join(TEST_ROOT, "results", "graphs")

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
        "title": "Solving Time",
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


BSP_THEME = {
    "variant_labels": {
        "gc": "G&S + Clingo sem",
        "gc_aux": "G&S + Clingo sem + Aux",
        "ga": "G&S + Alpha sem",
        "la": "Lazy + Alpha sem",
        "lc": "Lazy + Clingo sem",
        "la_aux": "Lazy + Alpha sem + Aux",
        "la_co": "Lazy + Optimized Constraint (BSP_la_co.lp)",
    },
    "variant_files": {
        "gc": "encodings/BSP/BSP_gc.lp",
        "gc_aux": "encodings/BSP/BSP_gc_aux.lp",
        "ga": "encodings/BSP/BSP_ga.lp",
        "la": "encodings/BSP/BSP_la.lp",
        "lc": "encodings/BSP/BSP_lc.lp",
        "la_aux": "encodings/BSP/BSP_la_aux.lp",
        "la_co": "encodings/BSP/BSP_la_co.lp",
    },
    "variant_colors": {
        "gc":  "#E74C3C",
        "gc_aux": "#C0392B",
        "ga": "#F39C12",
        "la":   "#2ECC71",
        "lc": "#9B59B6",
        "la_aux": "#16A085",
        "la_co": "#3498DB",
    },
    "variant_markers": {
        "gc":  "o",
        "gc_aux": "x",
        "ga": "v",
        "la":   "s",
        "lc": "D",
        "la_aux": "P",
        "la_co": "^",
    },
    "variant_order": ["gc", "gc_aux", "ga", "la", "lc", "la_aux", "la_co"],
    "xlabel": "Problem size (N)",
    "suptitle": "BSP Benchmark: Standard vs Lazy Heuristic Grounding",
    "baseline": "gc",
}


PUP_THEME = {
    "variant_labels": {
        "pup":        "Dichiarativo (PUP.lp)",
        "pup_heur":   "Euristiche Statiche (PUP_heur.lp)",
        "pup_double_std": "PUP Double #heuristic",
        "pup_double_aux": "PUP Double #heuristic + Aux",
        "pup_double": "Aggregati Dinamici (PUP_double_l.lp)",
        "pup_double_aux_l": "Aggregati Dinamici + Aux",
        "pup_doublev_std": "PUP DoubleV #heuristic",
        "pup_doublev_aux": "PUP DoubleV #heuristic + Aux",
        "pup_doublev":"Aggregati Dinamici Variante (PUP_double_variant_l.lp)",
        "pup_doublev_aux_l": "Aggregati Dinamici Variante + Aux",
    },
    "variant_files": {
        "pup": "encodings/PUP/PUP.lp",
        "pup_heur": "encodings/PUP/PUP_heur.lp",
        "pup_double_std": "encodings/PUP/PUP_double.lp",
        "pup_double_aux": "encodings/PUP/PUP_double_aux.lp",
        "pup_double": "encodings/PUP/PUP_double_l.lp",
        "pup_double_aux_l": "encodings/PUP/PUP_double_aux_l.lp",
        "pup_doublev_std": "encodings/PUP/PUP_double_variant.lp",
        "pup_doublev_aux": "encodings/PUP/PUP_double_variant_aux.lp",
        "pup_doublev": "encodings/PUP/PUP_double_variant_l.lp",
        "pup_doublev_aux_l": "encodings/PUP/PUP_double_variant_aux_l.lp",
    },
    "variant_colors": {
        "pup":        "#E74C3C",
        "pup_heur":   "#F39C12",
        "pup_double_std": "#8E44AD",
        "pup_double_aux": "#6C3483",
        "pup_double": "#2ECC71",
        "pup_double_aux_l": "#16A085",
        "pup_doublev_std": "#8E44AD",
        "pup_doublev_aux": "#6C3483",
        "pup_doublev":"#9B59B6",
        "pup_doublev_aux_l": "#16A085",
    },
    "variant_markers": {
        "pup":        "o",
        "pup_heur":   "D",
        "pup_double_std": "X",
        "pup_double_aux": "P",
        "pup_double": "s",
        "pup_double_aux_l": "*",
        "pup_doublev_std": "X",
        "pup_doublev_aux": "P",
        "pup_doublev":"^",
        "pup_doublev_aux_l": "*",
    },
    "variant_order": [
        "pup",
        "pup_heur",
        "pup_double_std",
        "pup_double_aux",
        "pup_double",
        "pup_double_aux_l",
        "pup_doublev_std",
        "pup_doublev_aux",
        "pup_doublev",
        "pup_doublev_aux_l",
    ],
    "xlabel": "Instance size (N)",
    "baseline": "pup",
}


def load_csv(csv_path: str):


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


VARIANT_FILL_ALPHA = 0.15
CAPTION_COLOR = "#5F6368"
SEPARATOR_COLOR = "#D6D6D6"
VERTICAL_SEPARATOR_GAP_FRACTION = 0.42
THOUSAND_FORMAT_METRICS = {
    "variables",
    "combined_heuristics",
}
MILLION_FORMAT_METRICS = {
    "ground_lines",
}


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

    abs_value = abs(value)
    if abs_value >= 100_000:
        scaled = value / 1_000_000
        return f"{scaled:.1f}".rstrip("0").rstrip(".") + "M"
    if abs_value >= 1:
        return f"{value:.0f}"
    if value == 0:
        return "0"
    return f"{value:g}"


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


def _format_memory_mb(value, _pos=None):

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

    from matplotlib.ticker import FuncFormatter, MaxNLocator

    if metric == "memory_mb":
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6))
        ax.yaxis.set_major_formatter(FuncFormatter(_format_memory_mb))
    elif metric in THOUSAND_FORMAT_METRICS:
        ax.yaxis.set_major_locator(MaxNLocator(nbins=6, integer=True))
        ax.yaxis.set_major_formatter(FuncFormatter(_format_thousands))
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
    if not filename:
        return set()

    basename = os.path.basename(filename.replace("\\", "/")).lower()
    return {
        basename,
        _compact_filename_stem(filename),
    }


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
        if stem.startswith("BSP_"):
            stem = stem[len("BSP_"):]
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
            gc = np.array(data["gc"])

            color = colors.get(variant, None)
            label = labels.get(variant, variant)
            marker = markers.get(variant, "o")

            ax.plot(n, mean, marker=marker, label=label, color=color,
                    linewidth=1.8, markersize=5, zorder=3)
            ax.fill_between(n, mean - gc, mean + gc,
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
        gc = np.array(data["gc"])

        color = colors.get(variant, None)
        label = labels.get(variant, variant)
        marker = markers_map.get(variant, "o")

        ax.plot(n, mean, marker=marker, label=label, color=color,
                linewidth=2, markersize=6, zorder=3)
        ax.fill_between(n, mean - gc, mean + gc,
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

    if metric not in stats.get(variant, {}):
        return {}
    data = stats[variant][metric]
    return dict(zip(data["n"], data["mean"]))


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
        "ground_lines" in stats.get(baseline_variant, {}) and
        "ground_lines" in stats.get(variant, {})
    ):
        return "ground_lines"
    return "rules"


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
        print("  /tmp/clingo-graphs-venv/bin/python -m pip install -r test_folder/tools/requirements.txt")
        print("  /tmp/clingo-graphs-venv/bin/python test_folder/tools/gen_graphs.py")
        sys.exit(1)


def process_csv(csv_path, graphs_dir, theme, problem_name, title_suffix="", excluded_variants=None):

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
        description="Generate BSP/PUP benchmark charts from CSV result files.",
        epilog=f"""
{heading("Commands")}
  {cmd("%(prog)s")}
      Generate every standard chart: BSP and PUP, without exclusions.

  {cmd("%(prog)s --reset")}
      Empty the graph output directory and exit. This is the only command
      that removes existing graph files.

  {cmd("%(prog)s --type bsp")}
      Generate only standard BSP charts.

  {cmd("%(prog)s --type bsp --exclude bspga,bspgcaux")}
      Generate BSP charts in a separate exclusion directory, without the
      selected variants.

  {cmd("%(prog)s --results-dir DIR --out DIR")}
      Read result CSV files from a custom directory and write charts elsewhere.

{heading("Expected CSV files")}
  {value("bsp_results.csv")}          BSP benchmark results.
  {value("pup_double_results.csv")}   PUP Double-family benchmark results.
  {value("pup_doublev_results.csv")}  PUP DoubleV-family benchmark results.
  {value("results.csv")}              legacy BSP fallback.

{heading("Output directories")}
  {value("results/graphs/bsp/standard/")}      BSP charts with all variants.
  {value("results/graphs/bsp/no_<variant>/")}  BSP charts with selected variants removed.
  {value("results/graphs/pup/")}               PUP Double and DoubleV charts.

{heading("Options")}
  {opt("--results-dir DIR")}
      Directory containing benchmark CSV files. Default: results/.

  {opt("--out DIR")}
      Base output directory for generated PNG charts. Default: graphs.

  {opt("--type {bsp,pup}")}
      Restrict generation to one benchmark family. Required when using
      --exclude.

  {opt("--reset")}
      Empty the graph output directory and exit.

  {opt("--exclude SELECTOR")}
      Exclude matching variants for the selected --type. Accepts exact filenames with
      extension, or compact file stems: lowercase, without spaces,
      underscores, or extension. Can be repeated or comma-separated.

{heading("Selector examples")}
  {value("BSP_ga.lp")}                  exact filename.
  {value("bspga")}                      compact BSP file stem.
  {value("PUP_double_aux_l.lp")}        exact filename.
  {value("pupdoubleauxl")}              compact PUP file stem.

{heading("Examples")}
  {cmd("%(prog)s")}
      Generate every chart with default paths.

  {cmd("%(prog)s --results-dir ../results --out ../results/graphs")}
      Explicit paths when running from test_folder/tools.

  {cmd("%(prog)s --type bsp --exclude BSP_lc.lp")}
      Exclude the BSP_lc.lp variant from a separate BSP graph set.

  {cmd("%(prog)s --type bsp --exclude bspla,bspgcaux, BSP_la_co.lp")}
      Exclude several variants with a comma-separated list.

  {cmd("%(prog)s --type bsp --exclude bspla,bspgcaux --exclude BSP_la_co.lp")}
      Exclude several variants in one run.
        """.strip(),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--results-dir",
        default=DEFAULT_RESULTS_DIR,
        metavar="DIR",
        help=(
            f"Directory containing benchmark CSV files. Default: {DEFAULT_RESULTS_DIR}."
        ),
    )
    parser.add_argument(
        "--out",
        default=DEFAULT_GRAPHS_DIR,
        metavar="DIR",
        help=(
            f"Base directory for generated PNG charts. Default: {DEFAULT_GRAPHS_DIR}."
        ),
    )
    parser.add_argument(
        "--exclude",
        action="append",
        nargs="+",
        default=[],
        metavar="SELECTOR",
        help=(
            "Exclude variants for the selected --type. Accepts exact filenames with extension "
            "or compact file stems: lowercase, without spaces, underscores, or "
            "extension. Repeat it or use comma-separated values."
        ),
    )
    parser.add_argument(
        "--type",
        choices=("bsp", "pup"),
        default=None,
        help=(
            "Generate only one benchmark family. Required when using --exclude. "
            "Without --type and without --exclude, all standard charts are generated."
        ),
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Empty the graph output directory and exit.",
    )

    args = parser.parse_args()
    exclude_selectors = _split_exclude_selectors(args.exclude)
    if args.reset and (args.type or exclude_selectors):
        parser.error("--reset deve essere usato da solo: non combinare --reset con --type o --exclude.")
    if exclude_selectors and not args.type:
        parser.error("--exclude richiede --type bsp oppure --type pup.")
    return args


def build_themes():
    bsp_theme = BSP_THEME.copy()
    bsp_theme["suptitle"] = "BSP Benchmark: Standard vs Lazy Heuristic Grounding"

    pup_double_theme = PUP_THEME.copy()
    pup_double_theme["suptitle"] = "PUP Benchmark — Double Family"
    pup_double_theme["heuristic_baseline"] = "pup_double_std"

    pup_doublev_theme = PUP_THEME.copy()
    pup_doublev_theme["suptitle"] = "PUP Benchmark — DoubleV Family"
    pup_doublev_theme["heuristic_baseline"] = "pup_doublev_std"

    return bsp_theme, pup_double_theme, pup_doublev_theme


def process_bsp(results_dir, base_out, exclude_selectors):
    bsp_csv = os.path.join(results_dir, "bsp_results.csv")
    bsp_theme, _, _ = build_themes()

    bsp_user_excluded_order = resolve_excluded_variant_list_quiet(
        bsp_theme,
        exclude_selectors,
    )
    bsp_excluded = set(bsp_user_excluded_order)
    bsp_label = "BSP (Balanced Sum Partition)"
    bsp_out = os.path.join(
        base_out,
        "bsp",
        exclusion_dir_name(bsp_theme, bsp_excluded, bsp_user_excluded_order),
    )
    return process_csv(bsp_csv, bsp_out, bsp_theme, bsp_label, excluded_variants=bsp_excluded)


def process_pup(results_dir, base_out, exclude_selectors):
    _, pup_double_theme, pup_doublev_theme = build_themes()

    pup_double_excluded_order = resolve_excluded_variant_list_quiet(
        pup_double_theme,
        exclude_selectors,
    )
    pup_doublev_excluded_order = resolve_excluded_variant_list_quiet(
        pup_doublev_theme,
        exclude_selectors,
    )
    seen_double_exclusions = set(pup_double_excluded_order)
    ordered_exclusions = pup_double_excluded_order + [
        variant
        for variant in pup_doublev_excluded_order
        if variant not in seen_double_exclusions
    ]
    pup_excluded = set(ordered_exclusions)

    pup_out = os.path.join(base_out, "pup")
    if pup_excluded:
        pup_out = os.path.join(
            pup_out,
            exclusion_dir_name(pup_double_theme, pup_excluded, ordered_exclusions),
        )

    processed_any = False
    pup_double_csv = os.path.join(results_dir, "pup_double_results.csv")
    if process_csv(
        pup_double_csv,
        pup_out,
        pup_double_theme,
        "PUP Double",
        title_suffix="Double",
        excluded_variants=set(pup_double_excluded_order),
    ):
        processed_any = True

    pup_doublev_csv = os.path.join(results_dir, "pup_doublev_results.csv")
    if process_csv(
        pup_doublev_csv,
        pup_out,
        pup_doublev_theme,
        "PUP DoubleV",
        title_suffix="DoubleV",
        excluded_variants=set(pup_doublev_excluded_order),
    ):
        processed_any = True

    return processed_any


def main():
    args = parse_args()
    results_dir = args.results_dir
    base_out = args.out
    global_exclude_selectors = _split_exclude_selectors(args.exclude)

    if args.reset:
        reset_graphs_dir(base_out)
        return

    bsp_theme, pup_double_theme, pup_doublev_theme = build_themes()
    selected_themes = {
        "bsp": [bsp_theme],
        "pup": [pup_double_theme, pup_doublev_theme],
        None: [bsp_theme, pup_double_theme, pup_doublev_theme],
    }[args.type]
    unknown_exclude_selectors = unmatched_exclude_selectors(
        global_exclude_selectors,
        selected_themes,
    )
    if unknown_exclude_selectors:
        print(
            "[ERROR] exclude selector non validi per "
            f"--type {args.type}: {', '.join(unknown_exclude_selectors)}"
        )
        sys.exit(2)

    expected_csvs = [
        os.path.join(results_dir, "bsp_results.csv"),
        os.path.join(results_dir, "pup_double_results.csv"),
        os.path.join(results_dir, "pup_doublev_results.csv"),
        os.path.join(results_dir, "results.csv"),
    ]
    if any(os.path.isfile(path) for path in expected_csvs):
        ensure_plot_dependencies()

    processed_any = False
    if args.type in (None, "bsp"):
        if process_bsp(results_dir, base_out, global_exclude_selectors):
            processed_any = True

    if args.type in (None, "pup"):
        if process_pup(results_dir, base_out, global_exclude_selectors):
            processed_any = True

    legacy_csv = os.path.join(results_dir, "results.csv")
    if args.type in (None, "bsp") and not processed_any and os.path.isfile(legacy_csv):
        print(f"\n[FALLBACK] Trovato file legacy '{legacy_csv}', lo processo come BSP...")
        legacy_out = os.path.join(base_out, "bsp", "standard")
        process_csv(legacy_csv, legacy_out, BSP_THEME,
                    "BSP (Legacy)", title_suffix="legacy",
                    excluded_variants=resolve_excluded_variants(
                        BSP_THEME,
                        global_exclude_selectors,
                        context="BSP legacy",
                    ))
        processed_any = True

    if not processed_any:
        print("\nNessun file CSV di risultati trovato.")
        print("Esegui prima benchmarks/benchmark_bsp.sh e/o benchmarks/benchmark_pup.sh.")
        sys.exit(1)

    print(f"\nDone. Tutti i grafici sono in '{base_out}/'.")


if __name__ == "__main__":
    main()
