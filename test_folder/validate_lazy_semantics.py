#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


SUCCESS_STATUSES = {0, 10, 20, 30}


def find_clingo(explicit_path: str | None) -> str:
    if explicit_path:
        return explicit_path

    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent
    candidates = [
        repo_root / "build" / "bin" / "clingo",
        repo_root / "clingo-modified" / "build" / "bin" / "clingo",
    ]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)

    return "clingo"


def run_clingo(clingo: str, files: list[str], seed: int, models: int, constants: list[str], extra: list[str]):
    cmd = [clingo, *files, "--outf=2", f"--seed={seed}", "-n", str(models)]
    for const in constants:
        cmd.extend(["-c", const])
    cmd.extend(extra)

    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode not in SUCCESS_STATUSES:
        raise RuntimeError(
            "clingo failed with status "
            f"{proc.returncode}\ncommand: {' '.join(cmd)}\n{proc.stderr}"
        )

    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"cannot parse clingo JSON output: {exc}\ncommand: {' '.join(cmd)}\n{proc.stdout[:500]}"
        ) from exc

    return cmd, data


def is_internal_symbol(symbol: str) -> bool:
    return symbol.startswith("__")


def witness_sets(data: dict, ignore_internal: bool):
    models = []
    costs = []
    for call in data.get("Call", []):
        for witness in call.get("Witnesses", []):
            values = witness.get("Value", [])
            if ignore_internal:
                values = [symbol for symbol in values if not is_internal_symbol(symbol)]
            models.append(tuple(sorted(values)))
            if "Costs" in witness:
                costs.append(tuple(witness["Costs"]))
    return tuple(sorted(models)), tuple(sorted(costs))


def comparable_result(data: dict, mode: str, ignore_internal: bool):
    result = data.get("Result", "UNKNOWN")
    models, costs = witness_sets(data, ignore_internal)
    optimum = data.get("Models", {}).get("Optimum")

    if mode == "result":
        return {"result": result}
    if mode == "optimum":
        return {"result": result, "costs": costs, "optimum": optimum}
    return {"result": result, "models": models, "costs": costs, "optimum": optimum}


def compact_result(result: dict, sample_size: int = 3) -> dict:
    compact = dict(result)
    if "models" in compact:
        models = compact.pop("models")
        compact["model_count"] = len(models)
        compact["model_sample"] = models[:sample_size]
    if "costs" in compact:
        costs = compact.pop("costs")
        compact["cost_count"] = len(costs)
        compact["cost_sample"] = costs[:sample_size]
    return compact


def print_model_delta(base_result: dict, lazy_result: dict, sample_size: int = 3):
    if "models" not in base_result or "models" not in lazy_result:
        return

    base_models = set(base_result["models"])
    lazy_models = set(lazy_result["models"])
    missing = sorted(base_models - lazy_models)
    extra = sorted(lazy_models - base_models)
    print(f"  missing models in lazy: {len(missing)}")
    for model in missing[:sample_size]:
        print(f"    - {model}")
    print(f"  extra models in lazy: {len(extra)}")
    for model in extra[:sample_size]:
        print(f"    + {model}")


def compare_instance(args, clingo: str, instance: str) -> bool:
    base_files = [*args.baseline, instance]
    lazy_files = [*args.lazy, instance]

    base_cmd, base_data = run_clingo(
        clingo, base_files, args.seed, args.models, args.constant, args.extra
    )
    lazy_cmd, lazy_data = run_clingo(
        clingo, lazy_files, args.seed, args.models, args.constant, args.extra
    )

    ignore_internal = not args.keep_internal
    base_result = comparable_result(base_data, args.compare, ignore_internal)
    lazy_result = comparable_result(lazy_data, args.compare, ignore_internal)
    ok = base_result == lazy_result

    label = Path(instance).name
    if ok:
        print(f"[OK] {label}")
        return True

    print(f"[FAIL] {label}")
    print(f"  baseline: {' '.join(base_cmd)}")
    print(f"  lazy:     {' '.join(lazy_cmd)}")
    print(f"  baseline result: {compact_result(base_result)}")
    print(f"  lazy result:     {compact_result(lazy_result)}")
    print_model_delta(base_result, lazy_result)
    return False


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compare the semantic output of a baseline ASP encoding and a lazy "
            "heuristic encoding on the same instances."
        )
    )
    parser.add_argument("--clingo", help="Path to the modified clingo binary.")
    parser.add_argument(
        "--baseline",
        nargs="+",
        required=True,
        help="Baseline encoding files. The instance is appended after these files.",
    )
    parser.add_argument(
        "--lazy",
        nargs="+",
        required=True,
        help="Lazy encoding files. The instance is appended after these files.",
    )
    parser.add_argument(
        "--instance",
        nargs="+",
        required=True,
        help="One or more instance files to validate.",
    )
    parser.add_argument(
        "--models",
        type=int,
        default=0,
        help="Number of models requested from clingo. Default: 0 (all models).",
    )
    parser.add_argument("--seed", type=int, default=1, help="Clingo random seed.")
    parser.add_argument(
        "-c",
        "--constant",
        action="append",
        default=[],
        metavar="NAME=VALUE",
        help="Constant passed to clingo. Can be repeated.",
    )
    parser.add_argument(
        "--compare",
        choices=["models", "optimum", "result"],
        default="models",
        help="Comparison strength. Default: models.",
    )
    parser.add_argument(
        "--keep-internal",
        action="store_true",
        help="Do not filter symbols whose printed name starts with '__'.",
    )
    parser.add_argument(
        "extra",
        nargs=argparse.REMAINDER,
        help="Extra clingo arguments after '--', for example -- --heuristic=Domain.",
    )

    args = parser.parse_args()
    if args.extra and args.extra[0] == "--":
        args.extra = args.extra[1:]

    clingo = find_clingo(args.clingo)
    failed = 0
    for instance in args.instance:
        if not compare_instance(args, clingo, instance):
            failed += 1

    if failed:
        print(f"\nSemantic validation failed on {failed} instance(s).", file=sys.stderr)
        return 1

    print("\nSemantic validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
