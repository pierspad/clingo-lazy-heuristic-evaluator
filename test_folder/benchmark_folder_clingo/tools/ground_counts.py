#!/usr/bin/env python3
"""Analisi DISACCOPPIATA dei conteggi di grounding delle euristiche.

Perche' separata dal benchmark cronometrato: il passo `clingo --text` stampa
l'INTERO programma ground e per le varianti ground-and-solve (g*) a n grande
puo' consumare moltissima memoria. Misurarlo nello stesso processo del solve
falserebbe `mem` (la metrica centrale della tesi). Qui e' un'analisi a parte,
strutturale e deterministica: non entra nelle curve di tempo/memoria.

Per ogni (backend, famiglia, variante, istanza) esegue il grounding testuale e
conta, replicando le convenzioni dello storico runner:
  ground_heuristics              direttive `#heuristic` espanse dal grounder
  ground_lazy_heuristic_facts    fatti-template `__heuristic(...)`
  ground_prolog_heuristic_facts  fatti `prolog_heuristic(...)` / `heuristic("...")`
  ground_query_heuristic_facts   = prolog_heuristic_facts (alias storico)
  ground_facts                   fatti totali (righe che finiscono con '.', no ':-')
  ground_lines                   righe totali dell'output ground

NOTA DI CONFRONTO EQUO: per g* ogni `#heuristic` ground e' lavoro realmente
materializzato; per le lazy/native i `__heuristic` sono UN template che a
runtime genera N candidati (non passano dal grounder). Quindi i conteggi lazy
SOTTOSTIMANO il lavoro runtime: quello vero si legge su decide_calls /
total_decide_time_ms (backend prolog) nel benchmark principale.

Uso:
    python3 tools/ground_counts.py                       # tutto, CSV su output/
    python3 tools/ground_counts.py --families BSP
    python3 tools/ground_counts.py --csv output/ground_counts.csv
    CLINGO_BIN=/path/to/clingo python3 tools/ground_counts.py
"""
from __future__ import annotations

import argparse
import csv
import re
import resource
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]   # benchmark_folder_clingo (btool cwd: benchmarks/, output/)
TEST_FOLDER = ROOT.parent                     # test_folder (encodings-*, instances/)
REPO = ROOT.parents[1]                         # repo root (clingo-native/, clingo-prolog/)

# Varianti per famiglia (coerenti col runscript).
COMMON = ["gc_noheur", "gc", "ga", "la", "lc"]
BSP_ONLY = ["ga_weak", "la_aux", "la_co"]
VARIANTS = {
    "BSP": COMMON + BSP_ONLY,
    "PUP": COMMON,
    "HRP": COMMON,
}
ENC_SUBDIR = {"BSP": "1_BSP", "PUP": "2_PUP", "HRP": "3_HRP"}
ENC_PREFIX = {"BSP": "BSP", "PUP": "PUP", "HRP": "HRP"}
INSTANCE_RE = re.compile(r"-(\d+)")

FIELDS = [
    "backend", "family", "variant", "instance", "size", "status",
    "ground_text_wall_s", "ground_heuristics", "ground_lazy_heuristic_facts",
    "ground_prolog_heuristic_facts", "ground_query_heuristic_facts",
    "ground_facts", "ground_lines",
]
SUCCESS = {0, 10, 20, 30}


def clingo_for(backend: str) -> str:
    import os
    if os.environ.get("CLINGO_BIN"):
        return os.environ["CLINGO_BIN"]
    return str(REPO / f"clingo-{backend}" / "build" / "bin" / "clingo")


def mem_limit(limit_bytes: int):
    def pre():
        resource.setrlimit(resource.RLIMIT_AS, (limit_bytes, limit_bytes))
    return pre


def count_ground(text: str) -> dict[str, int]:
    heuristics = lazy = prolog = facts = lines = 0
    for line in text.splitlines():
        lines += 1
        s = line.strip()
        if s.startswith("#heuristic"):
            heuristics += 1
            continue
        if s.startswith("__heuristic("):
            lazy += 1
            facts += 1
            continue
        if s.startswith("prolog_heuristic(") or (s.startswith("heuristic(") and '"' in s):
            prolog += 1
            facts += 1
            continue
        if not s or s.startswith("%"):
            continue
        if s.endswith(".") and ":-" not in s:
            facts += 1
    return {
        "ground_heuristics": heuristics,
        "ground_lazy_heuristic_facts": lazy,
        "ground_prolog_heuristic_facts": prolog,
        "ground_query_heuristic_facts": prolog,
        "ground_facts": facts,
        "ground_lines": lines,
    }


def instances_for(family: str) -> list[Path]:
    d = ROOT / "benchmarks" / family
    return sorted(d.glob("*"))


def size_of(path: Path) -> str:
    m = INSTANCE_RE.search(path.stem)
    return m.group(1) if m else path.stem


def main() -> None:
    ap = argparse.ArgumentParser(description="Conteggi di grounding (disaccoppiati).")
    ap.add_argument("--backends", nargs="+", default=["native", "prolog"])
    ap.add_argument("--families", nargs="+", default=["BSP", "PUP", "HRP"])
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--memory-gb", type=float, default=8.0)
    ap.add_argument("--csv", type=Path, default=ROOT / "output" / "ground_counts.csv")
    args = ap.parse_args()

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    mem_bytes = int(args.memory_gb * 1024 ** 3)

    with open(args.csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        for backend in args.backends:
            clingo = clingo_for(backend)
            if not Path(clingo).is_file():
                print(f"!! clingo {backend} non trovato: {clingo} (skip)")
                continue
            for family in args.families:
                enc_dir = TEST_FOLDER / f"encodings-{backend}" / ENC_SUBDIR[family]
                for variant in VARIANTS[family]:
                    enc = enc_dir / f"{ENC_PREFIX[family]}_{variant}.lp"
                    if not enc.is_file():
                        continue
                    for inst in instances_for(family):
                        cmd = [clingo, str(inst), str(enc), "--heuristic=Domain", "--text"]
                        row = {
                            "backend": backend, "family": family, "variant": variant,
                            "instance": inst.stem, "size": size_of(inst),
                        }
                        start = time.perf_counter()
                        try:
                            proc = subprocess.run(
                                cmd, text=True, capture_output=True,
                                timeout=args.timeout, preexec_fn=mem_limit(mem_bytes),
                            )
                        except subprocess.TimeoutExpired:
                            row.update(status="timeout", ground_text_wall_s=f"{time.perf_counter()-start:.3f}")
                            w.writerow(row); fh.flush(); continue
                        except OSError as e:
                            row.update(status=f"error:{e}", ground_text_wall_s=f"{time.perf_counter()-start:.3f}")
                            w.writerow(row); fh.flush(); continue
                        wall = f"{time.perf_counter()-start:.3f}"
                        if proc.returncode not in SUCCESS:
                            row.update(status=f"exit_{proc.returncode}", ground_text_wall_s=wall)
                            w.writerow(row); fh.flush(); continue
                        counts = count_ground(proc.stdout)
                        row.update(status="ok", ground_text_wall_s=wall, **counts)
                        w.writerow(row); fh.flush()
                        print(f"  {backend} {family} {variant} {inst.stem}: "
                              f"heur={counts['ground_heuristics']} "
                              f"lazy={counts['ground_lazy_heuristic_facts']} "
                              f"facts={counts['ground_facts']}")
    print(f"\nScritto {args.csv}")


if __name__ == "__main__":
    main()
