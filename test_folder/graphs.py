"""
graphs.py
Legge i risultati multi-seed da ./test-results/results.csv e genera grafici
con media ± deviazione standard per ogni metrica CDNL.

Grafici generati (3×2):
  1. Tempo di Solving (netto CDNL)
  2. Tempo Totale (grounding + solving)
  3. Choices (decisioni del solver)
  4. Conflicts (conflitti / backtracking)
  5. Rules (dimensione grounding)
  6. Memoria RSS

Ogni punto è media su N seed; la banda colorata mostra ±1σ.
"""

import argparse
import csv
import os
import sys
from collections import defaultdict

DEFAULT_CSV = os.path.join("test-results", "results.csv")
DEFAULT_GRAPHS_DIR = "graphs"


# ============================================================================
# Caricamento CSV con supporto multi-seed
# ============================================================================

def load_csv(csv_path: str):
    """
    Carica il CSV e raggruppa i dati per (variant, n).
    Restituisce:
      {variant: {n: {metric: [values_per_seed]}}}
    """
    raw = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            variant = row["variant"].strip()
            n = int(row["n"])

            for metric in ["solving_s", "total_s", "choices", "conflicts",
                           "restarts", "rules", "variables", "memory_mb"]:
                val_str = row.get(metric, "").strip()
                if val_str not in ("NA", ""):
                    try:
                        raw[variant][n][metric].append(float(val_str))
                    except ValueError:
                        pass

    return raw


def compute_stats(raw):
    """
    Calcola media e deviazione standard per ogni (variant, n, metric).
    Restituisce:
      {variant: {metric: {"n": [...], "mean": [...], "std": [...]}}}
    """
    import statistics

    result = {}
    for variant, n_data in raw.items():
        result[variant] = defaultdict(lambda: {"n": [], "mean": [], "std": []})
        for n in sorted(n_data.keys()):
            for metric, values in n_data[n].items():
                if len(values) > 0:
                    mean_val = statistics.mean(values)
                    std_val = statistics.pstdev(values) if len(values) > 1 else 0.0
                    result[variant][metric]["n"].append(n)
                    result[variant][metric]["mean"].append(mean_val)
                    result[variant][metric]["std"].append(std_val)

    return result


# ============================================================================
# Configurazione visuale
# ============================================================================

VARIANT_LABELS = {
    "std": "Clingo Standard",
    "mod": "Clingo Lazy (Modificato)",
    "mod_opt": "Clingo Lazy (Constraint Ottimizzato)",
}
VARIANT_COLORS = {
    "std": "#E74C3C",   # rosso elegante
    "mod": "#2ECC71",   # verde elegante
    "mod_opt": "#3498DB",  # blu elegante
}
VARIANT_FILL_ALPHA = 0.15
VARIANT_MARKERS = {
    "std": "o",
    "mod": "s",
    "mod_opt": "^",
}
VARIANT_ORDER = ["std", "mod", "mod_opt"]


def _ordered_variants(stats: dict):
    """Ordina le varianti in modo stabile, mantenendo eventuali varianti extra in coda."""
    present = set(stats.keys())
    ordered = [v for v in VARIANT_ORDER if v in present]
    ordered.extend(sorted(present - set(ordered)))
    return ordered

# Definizione dei 6 grafici
PLOT_CONFIGS = [
    {
        "metric": "solving_s",
        "title": "Tempo di Solving (CDNL)",
        "ylabel": "Tempo (secondi)",
        "description": "Tempo netto speso nel search CDNL\n(escluso grounding)",
    },
    {
        "metric": "total_s",
        "title": "Tempo Totale",
        "ylabel": "Tempo (secondi)",
        "description": "Grounding + Solving",
    },
    {
        "metric": "choices",
        "title": "Choices (Decisioni)",
        "ylabel": "Numero di scelte",
        "description": "Se l'euristica lazy guida correttamente,\nle choices sono comparabili",
    },
    {
        "metric": "conflicts",
        "title": "Conflicts",
        "ylabel": "Numero di conflitti",
        "description": "Conflitti generati → backtracking.\nMeno conflitti = euristica migliore",
    },
    {
        "metric": "rules",
        "title": "Regole Ground",
        "ylabel": "Numero di regole",
        "description": "Dimensione del ground program.\nIl lazy dovrebbe generare meno regole",
    },
    {
        "metric": "memory_mb",
        "title": "Memoria RSS",
        "ylabel": "Memoria (MB)",
        "description": "Picco di memoria massima allocata",
    },
]


# ============================================================================
# Generazione grafici
# ============================================================================

def generate_graphs(stats: dict, graphs_dir: str):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import numpy as np
        from matplotlib.ticker import MaxNLocator
    except ImportError:
        print("Matplotlib non installato. Per abilitarlo: pip install matplotlib numpy")
        sys.exit(1)

    os.makedirs(graphs_dir, exist_ok=True)

    # Font professionale
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

    fig, axes = plt.subplots(3, 2, figsize=(14, 16))
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

            # Banda ±1σ
            ax.fill_between(n, mean - std, mean + std,
                            alpha=VARIANT_FILL_ALPHA, color=color, zorder=2)

        ax.set_title(config["title"])
        ax.set_xlabel("Dimensione del problema (N)")
        ax.set_ylabel(config["ylabel"])
        ax.legend(loc="upper left")

        # I conflitti sono conteggi discreti: mostra solo tacche intere sull'asse Y.
        if metric == "conflicts":
            ax.yaxis.set_major_locator(MaxNLocator(integer=True))

        # Annotazione descrittiva
        ax.text(0.98, 0.02, config["description"],
                transform=ax.transAxes, fontsize=7, color="#666",
                ha="right", va="bottom",
                fontstyle="italic")

        if not has_data:
            ax.text(0.5, 0.5, "Nessun dato", transform=ax.transAxes,
                    ha="center", va="center", fontsize=14, color="#CCC")

    fig.suptitle("Benchmark BSP: Standard e Varianti Lazy Heuristic Grounding\n"
                 f"(media ± σ su {_detect_seeds(stats)} seed per punto)",
                 fontsize=14, fontweight="bold", y=0.98)

    plt.tight_layout(rect=[0, 0, 1, 0.96])

    out_path = os.path.join(graphs_dir, "benchmark_results.png")
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"Grafico principale salvato in '{out_path}'.")

    # --- Grafico singolo: solo Solving Time (per tesi) ---
    _generate_single_chart(stats, graphs_dir, "solving_s",
                           "Tempo di Solving (CDNL netto)",
                           "Tempo (secondi)",
                           "solving_time.png")

    # --- Grafico singolo: Choices comparison ---
    _generate_single_chart(stats, graphs_dir, "choices",
                           "Choices — Qualità dell'euristica",
                           "Numero di scelte",
                           "choices_comparison.png")

    # --- Grafico singolo: Rules (grounding) ---
    _generate_single_chart(stats, graphs_dir, "rules",
                           "Dimensione del Ground Program",
                           "Numero di regole",
                           "rules_comparison.png")


def _generate_single_chart(stats, graphs_dir, metric, title, ylabel, filename):
    """Genera un singolo grafico per una metrica (utile per la tesi)."""
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
    ax.set_xlabel("Dimensione del problema (N)", fontsize=11)
    ax.set_ylabel(ylabel, fontsize=11)
    ax.legend(fontsize=10)
    ax.grid(True, alpha=0.3, linestyle="--")
    if metric == "conflicts":
        ax.yaxis.set_major_locator(MaxNLocator(integer=True))

    plt.tight_layout()
    out_path = os.path.join(graphs_dir, filename)
    plt.savefig(out_path, dpi=200, bbox_inches="tight")
    plt.close()
    print(f"Grafico '{filename}' salvato in '{out_path}'.")


def _detect_seeds(stats):
    """Rileva il numero di seed dal primo variant/metric disponibile."""
    for variant in stats.values():
        for metric in variant.values():
            if metric["n"]:
                return "N"  # Placeholder se non determinabile dal stats
    return "?"


# ============================================================================
# Tabella riepilogativa
# ============================================================================

def print_summary_table(stats):
    """Stampa una tabella riepilogativa con le medie per le metriche chiave."""
    variants = _ordered_variants(stats)
    table_width = 8 + len(variants) * 38

    print(f"\n{'='*table_width}")
    print(f"{'N':>5}  ", end="")
    for v in variants:
        label = VARIANT_LABELS.get(v, v)
        print(f"  {label:>35}", end="")
    print()
    print(f"{'':>5}  ", end="")
    for _ in variants:
        print(f"  {'Solving(s)':>10} {'Choices':>8} {'Confl.':>8} {'Rules':>7}", end="")
    print()
    print("-" * table_width)

    # Raccogli tutti gli N
    all_ns = set()
    for v in variants:
        for metric_data in stats[v].values():
            all_ns.update(metric_data["n"])

    for n in sorted(all_ns):
        row = f"{n:>5}  "
        for v in variants:
            solving = _get_mean_at_n(stats[v], "solving_s", n)
            choices = _get_mean_at_n(stats[v], "choices", n)
            conflicts = _get_mean_at_n(stats[v], "conflicts", n)
            rules = _get_mean_at_n(stats[v], "rules", n)

            s_str = f"{solving:.4f}" if solving is not None else "N/A"
            c_str = f"{choices:.0f}" if choices is not None else "N/A"
            f_str = f"{conflicts:.0f}" if conflicts is not None else "N/A"
            r_str = f"{rules:.0f}" if rules is not None else "N/A"

            row += f"  {s_str:>10} {c_str:>8} {f_str:>8} {r_str:>7}"
        print(row)

    print(f"{'='*table_width}\n")


def _get_mean_at_n(variant_stats, metric, n):
    """Restituisce la media per un dato N, o None se non disponibile."""
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
        description="Genera grafici dai risultati del benchmark con statistiche CDNL (CSV multi-seed)."
    )
    parser.add_argument("--csv", default=DEFAULT_CSV,
                        help=f"Percorso del file CSV dei risultati (default: {DEFAULT_CSV})")
    parser.add_argument("--out", default=DEFAULT_GRAPHS_DIR,
                        help=f"Cartella di output per i grafici (default: {DEFAULT_GRAPHS_DIR})")
    return parser.parse_args()


def main():
    args = parse_args()

    if not os.path.isfile(args.csv):
        print(f"Errore: file CSV non trovato: '{args.csv}'")
        print("Esegui prima benchmark.sh per raccogliere i dati.")
        sys.exit(1)

    print(f"Caricamento risultati da '{args.csv}'...")
    raw = load_csv(args.csv)

    if not raw:
        print("Errore: il CSV è vuoto o non contiene dati validi.")
        sys.exit(1)

    print(f"Varianti trovate: {list(raw.keys())}")
    for variant, n_data in raw.items():
        ns = sorted(n_data.keys())
        sample_n = ns[0] if ns else None
        seeds = len(n_data[sample_n]["solving_s"]) if sample_n and "solving_s" in n_data[sample_n] else 0
        print(f"  {variant}: {len(ns)} valori di N, ~{seeds} seed per punto")

    stats = compute_stats(raw)

    print_summary_table(stats)
    generate_graphs(stats, args.out)


if __name__ == "__main__":
    main()
