#!/usr/bin/env python3
"""Genera le istanze BSP per benchmark-tool.

BSP e' parametrico nella costante `n`: l'encoding (BSP_<variant>.lp) usa `n`,
mentre l'istanza fornisce soltanto `#const n=N.`. benchmark-tool tratta ogni
file come un'istanza distinta, quindi materializziamo un file per ogni taglia.

Uso:
    python3 tools/gen_bsp_instances.py            # default: 3..30 step 1
    python3 tools/gen_bsp_instances.py --start 40 --end 100 --step 10
    python3 tools/gen_bsp_instances.py --out benchmarks/BSP
"""
from __future__ import annotations

import argparse
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser(description="Genera istanze BSP (#const n=N).")
    ap.add_argument("--start", type=int, default=3)
    ap.add_argument("--end", type=int, default=30)
    ap.add_argument("--step", type=int, default=1)
    ap.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "benchmarks" / "BSP",
    )
    ap.add_argument(
        "--clean",
        action="store_true",
        help="Rimuove i bsp-*.lp esistenti prima di rigenerare.",
    )
    args = ap.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    if args.clean:
        for old in args.out.glob("bsp-*.lp"):
            old.unlink()

    count = 0
    for n in range(args.start, args.end + 1, args.step):
        # zero-pad a 4 cifre per ordinamento lessicografico stabile.
        path = args.out / f"bsp-{n:04d}.lp"
        path.write_text(f"#const n={n}.\n", encoding="utf-8")
        count += 1

    print(f"Generate {count} istanze BSP in {args.out} (n={args.start}..{args.end} step {args.step})")


if __name__ == "__main__":
    main()
