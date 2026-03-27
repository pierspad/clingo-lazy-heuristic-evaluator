"""
benchmark.py
Legge i risultati da ./test-results/results.csv e genera grafici in ./graphs/
"""

import argparse
import csv
import os
import sys

DEFAULT_CSV = os.path.join("test-results", "results.csv")
DEFAULT_GRAPHS_DIR = "graphs"

def load_csv(csv_path: str):
    results = {}
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            variant = row["variant"].strip()
            if variant not in results:
                results[variant] = {"n": [], "time": [], "memory": []}

            n = int(row["n"])

            elapsed_raw = row["elapsed_s"].strip()
            elapsed = float(elapsed_raw) if elapsed_raw not in ("NA", "") else None

            mem_raw = row["memory_mb"].strip()
            memory = float(mem_raw) if mem_raw not in ("NA", "") else None

            results[variant]["n"].append(n)
            results[variant]["time"].append(elapsed)
            results[variant]["memory"].append(memory)

    return results

VARIANT_LABELS = {
    "std": "Clingo Standard",
    "mod": "Clingo Lazy (Modificato)",
}
VARIANT_COLORS = {
    "std": "red",
    "mod": "green",
}
VARIANT_MARKERS = {
    "std": "o",
    "mod": "s",
}

def _filter_none(xs, ys):
    pairs = [(x, y) for x, y in zip(xs, ys) if y is not None]
    if not pairs:
        return [], []
    return zip(*pairs)

def generate_graphs(results: dict, graphs_dir: str):
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("Matplotlib non installato: impossibile generare grafici. Per abilitarlo: pip install matplotlib")
        sys.exit(1)

    os.makedirs(graphs_dir, exist_ok=True)
    out_path = os.path.join(graphs_dir, "benchmark_results.png")

    plt.figure(figsize=(12, 5))

    # --- Grafico 1: Tempo ---
    plt.subplot(1, 2, 1)
    for variant, data in results.items():
        xs, ys = _filter_none(data["n"], data["time"])
        if xs:
            plt.plot(
                list(xs), list(ys),
                marker=VARIANT_MARKERS.get(variant, "o"),
                label=VARIANT_LABELS.get(variant, variant),
                color=VARIANT_COLORS.get(variant, None),
            )
    plt.title("Tempo di esecuzione")
    plt.xlabel("Dimensione del problema (N)")
    plt.ylabel("Tempo (Secondi)")
    plt.legend()
    plt.grid(True)

    # --- Grafico 2: Memoria ---
    plt.subplot(1, 2, 2)
    for variant, data in results.items():
        xs, ys = _filter_none(data["n"], data["memory"])
        if xs:
            plt.plot(
                list(xs), list(ys),
                marker=VARIANT_MARKERS.get(variant, "o"),
                label=VARIANT_LABELS.get(variant, variant),
                color=VARIANT_COLORS.get(variant, None),
            )
    plt.title("Consumo di Memoria (RSS)")
    plt.xlabel("Dimensione del problema (N)")
    plt.ylabel("Memoria massima allocata (MB)")
    plt.legend()
    plt.grid(True)

    plt.tight_layout()
    plt.savefig(out_path, dpi=300)
    plt.close()
    print(f"Grafico salvato in '{out_path}'.")

def parse_args():
    parser = argparse.ArgumentParser(description="Genera grafici dai risultati del benchmark (CSV).")
    parser.add_argument("--csv", default=DEFAULT_CSV, help=f"Percorso del file CSV dei risultati (default: {DEFAULT_CSV})")
    parser.add_argument("--out", default=DEFAULT_GRAPHS_DIR, help=f"Cartella di output per i grafici (default: {DEFAULT_GRAPHS_DIR})")
    return parser.parse_args()

def main():
    args = parse_args()

    if not os.path.isfile(args.csv):
        print(f"Errore: file CSV non trovato: '{args.csv}'")
        print("Esegui prima il file .sh per raccogliere i dati.")
        sys.exit(1)

    print(f"Caricamento risultati da '{args.csv}'...")
    results = load_csv(args.csv)

    if not results:
        print("Errore: il CSV è vuoto o non contiene dati validi.")
        sys.exit(1)

    variants = list(results.keys())
    all_ns = sorted({n for v in variants for n in results[v]["n"]})
    print(f"\n{'N':>5}  " + "  ".join(f"{VARIANT_LABELS.get(v,v):>30}" for v in variants))
    print("-" * (7 + 32 * len(variants)))
    for n in all_ns:
        row = f"{n:>5}  "
        for v in variants:
            data = results[v]
            if n in data["n"]:
                idx = data["n"].index(n)
                t = data["time"][idx]
                m = data["memory"][idx]
                t_str = f"{t:.4f}s" if t is not None else "N/A"
                m_str = f"{m:.2f}MB" if m is not None else "N/A"
                row += f"  {t_str:>10} / {m_str:>10}          "
            else:
                row += f"  {'---':>10} / {'---':>10}          "
        print(row)

    print()
    generate_graphs(results, args.out)

if __name__ == "__main__":
    main()
