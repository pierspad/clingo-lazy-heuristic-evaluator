#!/usr/bin/env python3

import argparse
import csv
import json
import os
import resource
import shlex
import signal
import subprocess
import sys
from pathlib import Path
from typing import Any


CSV_FIELDS = [
    "n",
    "variant",
    "seed",
    "setting",
    "clingo_extra_args",
    "status",
    "solver_status",
    "ground_status",
    "failure_reason",
    "exit_code",
    "memory_limit_hit",
    "solving_s",
    "total_s",
    "grounding_s",
    "choices",
    "conflicts",
    "restarts",
    "rules",
    "variables",
    "memory_mb",
    "ground_heuristics",
    "ground_lazy_heuristic_facts",
    "ground_prolog_heuristic_facts",
    "ground_facts",
    "ground_lines",
]

SUCCESS_STATUSES = {0, 10, 20, 30}
EXIT_OK = 0
EXIT_MEMORY = 75
EXIT_TIMEOUT = 124
EXIT_ERROR = 1

# ==============================================================================
# DEFAULT BENCHMARK PARAMETERS
# ==============================================================================
DEFAULT_MODELS = 1
DEFAULT_TIMEOUT = 120
DEFAULT_MEMORY_BYTES = 8 * 1024 * 1024 * 1024
DEFAULT_SEMANTICS = "native"
# ==============================================================================


def find_clingo(explicit_path: str | None) -> str:
    if explicit_path:
        return explicit_path

    test_root = Path(__file__).resolve().parents[1]
    repo_root = test_root.parent
    candidates = [
        repo_root / "build" / "bin" / "clingo",
        repo_root / "clingo-modified" / "build" / "bin" / "clingo",
    ]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)

    return "clingo"


def set_memory_limit(limit_bytes: int | None):
    if not limit_bytes:
        return None

    def preexec():
        resource.setrlimit(resource.RLIMIT_AS, (limit_bytes, limit_bytes))

    return preexec


def ordered_files(args) -> list[str]:
    if args.order == "encoding-first":
        return [*args.encoding, *args.instance]
    return [*args.instance, *args.encoding]


def build_clingo_command(args, clingo: str, *, json_mode: bool) -> list[str]:
    cmd = [clingo, *ordered_files(args)]
    for const in args.constant:
        cmd.extend(["-c", const])
    if args.domain_heuristic:
        cmd.append("--heuristic=Domain")
    if json_mode:
        cmd.extend(["--outf=2", "--stats=2", f"--seed={args.seed}", "-n", str(args.models)])
        cmd.append(f"--time-limit={args.timeout}")
        cmd.extend(args.clingo_option)
    else:
        cmd.append("--text")
    return cmd


def run_command(cmd: list[str], timeout: int, memory_bytes: int | None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    env["LC_NUMERIC"] = "C"
    return subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=set_memory_limit(memory_bytes),
        env=env,
    )


def nested_get(data: dict[str, Any], path: list[str], default="NA"):
    cur: Any = data
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def as_number(value, default="NA"):
    if isinstance(value, (int, float)):
        return value
    return default


def format_float(value, digits: int = 6):
    if value == "NA":
        return value
    return f"{float(value):.{digits}f}"


def parse_solver_metrics(data: dict[str, Any], memory_mb: str) -> dict[str, str]:
    total = as_number(nested_get(data, ["Time", "Total"]))
    solve = as_number(nested_get(data, ["Time", "Solve"]))
    if total != "NA" and solve != "NA":
        # Derived estimate from clingo JSON statistics, not a separate
        # wall-clock timer for grounding alone.
        grounding = max(float(total) - float(solve), 0.0)
    else:
        grounding = "NA"

    return {
        "solving_s": format_float(solve),
        "total_s": format_float(total),
        "grounding_s": format_float(grounding),
        "choices": str(as_number(nested_get(data, ["Stats", "Core", "Choices"]))),
        "conflicts": str(as_number(nested_get(data, ["Stats", "Core", "Conflicts"]))),
        "restarts": str(as_number(nested_get(data, ["Stats", "Core", "Restarts"]))),
        "rules": str(as_number(nested_get(data, ["Stats", "LP", "Rules", "Final"]))),
        "variables": str(as_number(nested_get(data, ["Stats", "Problem", "Variables"]))),
        "memory_mb": memory_mb,
    }


def failure_metrics(memory_mb: str = "NA") -> dict[str, str]:
    return {
        "solving_s": "NA",
        "total_s": "NA",
        "grounding_s": "NA",
        "choices": "NA",
        "conflicts": "NA",
        "restarts": "NA",
        "rules": "NA",
        "variables": "NA",
        "memory_mb": memory_mb,
    }


def ground_failure_metrics() -> dict[str, str]:
    return {
        "ground_heuristics": "NA",
        "ground_lazy_heuristic_facts": "NA",
        "ground_prolog_heuristic_facts": "NA",
        "ground_facts": "NA",
        "ground_lines": "NA",
    }


def sanitize_debug_name(value: str) -> str:
    return "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in str(value))


def dump_json_failure(args, proc: subprocess.CompletedProcess[str]) -> tuple[Path, Path]:
    test_root = Path(__file__).resolve().parents[1]
    debug_dir = test_root / "results" / "debug" / "json_failures"
    debug_dir.mkdir(parents=True, exist_ok=True)
    base = "_".join(
        [
            sanitize_debug_name(args.variant),
            f"n{sanitize_debug_name(args.size)}",
            f"seed{sanitize_debug_name(args.seed)}",
            sanitize_debug_name(args.setting),
        ]
    )
    stdout_path = debug_dir / f"{base}.stdout"
    stderr_path = debug_dir / f"{base}.stderr"
    stdout_path.write_text(proc.stdout, encoding="utf-8")
    stderr_path.write_text(proc.stderr, encoding="utf-8")
    return stdout_path, stderr_path


def _contains_memory_error(*texts: str) -> bool:
    joined = "\n".join(text for text in texts if text).lower()
    memory_markers = (
        "bad_alloc",
        "cannot allocate memory",
        "out of memory",
        "memory exhausted",
        "std::bad_alloc",
        "allocation failed",
    )
    return any(marker in joined for marker in memory_markers)


def _contains_clingo_timeout(*texts: str) -> bool:
    joined = "\n".join(text for text in texts if text).lower()
    timeout_markers = (
        "interrupted by signal",
        "time limit",
        "timelimit",
    )
    return any(marker in joined for marker in timeout_markers)


def classify_process_failure(proc: subprocess.CompletedProcess[str]) -> tuple[str, str]:
    if _contains_clingo_timeout(proc.stdout, proc.stderr):
        return "timeout", "clingo_time_limit"
    if _contains_memory_error(proc.stdout, proc.stderr):
        return "memory", "memory_limit"
    if proc.returncode < 0 and -proc.returncode in (signal.SIGKILL, signal.SIGSEGV):
        return "memory", f"signal_{-proc.returncode}"
    return "error", f"exit_{proc.returncode}"


def collect_ground_counts(args, clingo: str) -> tuple[dict[str, str], str]:
    cmd = build_clingo_command(args, clingo, json_mode=False)
    try:
        proc = run_command(cmd, args.timeout, args.memory_bytes)
    except subprocess.TimeoutExpired:
        return ground_failure_metrics(), "timeout"
    except OSError:
        return ground_failure_metrics(), "error"

    if proc.returncode not in SUCCESS_STATUSES:
        status, _reason = classify_process_failure(proc)
        return ground_failure_metrics(), status

    heuristics = 0
    lazy_facts = 0
    prolog_facts = 0
    facts = 0
    lines = 0
    for line in proc.stdout.splitlines():
        lines += 1
        stripped = line.strip()
        if stripped.startswith("#heuristic"):
            heuristics += 1
            continue
        if stripped.startswith("__heuristic("):
            lazy_facts += 1
            facts += 1
            continue
        if stripped.startswith("prolog_heuristic("):
            prolog_facts += 1
            facts += 1
            continue
        if not stripped or stripped.startswith("%"):
            continue
        if stripped.endswith(".") and ":-" not in stripped:
            facts += 1

    return {
        "ground_heuristics": str(heuristics),
        "ground_lazy_heuristic_facts": str(lazy_facts),
        "ground_prolog_heuristic_facts": str(prolog_facts),
        "ground_facts": str(facts),
        "ground_lines": str(lines),
    }, "ok"


def child_memory_mb() -> str:
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    # Linux reports ru_maxrss in KiB.
    return f"{usage.ru_maxrss / 1024:.4f}"


def memory_mb_to_gb(memory_mb: str) -> str:
    if memory_mb == "NA":
        return "NA"
    return f"{float(memory_mb) / 1024:.2f}"


def append_csv(csv_path: str, row: dict[str, str]):
    path = Path(csv_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    write_header = not path.exists() or path.stat().st_size == 0
    with path.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS)
        if write_header:
            writer.writeheader()
        writer.writerow({field: row.get(field, "NA") for field in CSV_FIELDS})


def run_benchmark(args) -> int:
    clingo = find_clingo(args.clingo)
    json_cmd = build_clingo_command(args, clingo, json_mode=True)
    row = {
        "n": args.size,
        "variant": args.variant,
        "seed": str(args.seed),
        "setting": args.setting,
        "clingo_extra_args": shlex.join(args.clingo_option) if args.clingo_option else "",
    }
    status = "ok"
    failure_reason = ""
    exit_code = EXIT_OK

    print(f"  [setting={args.setting} seed={args.seed}] {' '.join(json_cmd)}")
    try:
        proc = run_command(json_cmd, args.timeout + 5, args.memory_bytes)
    except subprocess.TimeoutExpired:
        print("    warning: timeout; solver metrics marked as NA", file=sys.stderr)
        row.update(failure_metrics(child_memory_mb()))
        status = "timeout"
        solver_status = "timeout"
        failure_reason = "solver_timeout"
        exit_code = EXIT_TIMEOUT
    except OSError as exc:
        print(f"    warning: cannot execute clingo: {exc}", file=sys.stderr)
        row.update(failure_metrics())
        status = "error"
        solver_status = "error"
        failure_reason = "exec_error"
        exit_code = EXIT_ERROR
    else:
        memory_mb = child_memory_mb()
        run_ok = proc.returncode in SUCCESS_STATUSES
        if run_ok:
            try:
                data = json.loads(proc.stdout)
            except json.JSONDecodeError as exc:
                stdout_path, stderr_path = dump_json_failure(args, proc)
                print(
                    "    warning: cannot parse clingo JSON: "
                    f"{exc}; stdout={stdout_path} stderr={stderr_path}",
                    file=sys.stderr,
                )
                run_ok = False
        if run_ok and data.get("Result") != "UNKNOWN":
            row.update(parse_solver_metrics(data, memory_mb))
            solver_status = "ok"
        else:
            if run_ok and data.get("Result") == "UNKNOWN":
                status = "timeout"
                solver_status = "timeout"
                failure_reason = "clingo_time_limit"
                exit_code = EXIT_TIMEOUT
            else:
                status, failure_reason = classify_process_failure(proc)
                solver_status = status
                if status == "memory":
                    exit_code = EXIT_MEMORY
                elif status == "timeout":
                    exit_code = EXIT_TIMEOUT
                else:
                    exit_code = EXIT_ERROR
            print(
                f"    warning: clingo exited with status {proc.returncode}; solver metrics marked as NA",
                file=sys.stderr,
            )
            if proc.stderr:
                print(proc.stderr.strip(), file=sys.stderr)
            row.update(failure_metrics(memory_mb))

    ground_counts, ground_status = collect_ground_counts(args, clingo)
    row.update(ground_counts)
    if ground_status == "memory":
        status = "memory"
        failure_reason = failure_reason or "ground_text_memory_limit"
        exit_code = EXIT_MEMORY
    elif status == "ok" and ground_status != "ok":
        failure_reason = f"ground_text_{ground_status}"

    row.update(
        {
            "status": status,
            "solver_status": solver_status,
            "ground_status": ground_status,
            "failure_reason": failure_reason,
            "exit_code": str(exit_code),
            "memory_limit_hit": "1" if status == "memory" else "0",
        }
    )
    append_csv(args.csv, row)

    display_row = {**row, "memory_gb": memory_mb_to_gb(row.get("memory_mb", "NA"))}
    print(
        "    status={status} reason={failure_reason} "
        "    grounding={grounding_s}s solving={solving_s}s total={total_s}s "
        "choices={choices} conflicts={conflicts} restarts={restarts} "
        "rules={rules} vars={variables} mem={memory_gb}GB "
        "heur={ground_heuristics} lazy_facts={ground_lazy_heuristic_facts} "
        "prolog_facts={ground_prolog_heuristic_facts} "
        "facts={ground_facts} ground_lines={ground_lines}".format(**display_row)
    )
    return exit_code


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run one clingo benchmark and append JSON-derived metrics to a CSV file."
    )
    parser.add_argument("--clingo", help="Path to the modified clingo binary.")
    parser.add_argument("--encoding", action="append", required=True, help="Encoding file. Can be repeated.")
    parser.add_argument("--instance", action="append", required=True, help="Instance/data file. Can be repeated.")
    parser.add_argument("--variant", required=True, help="Variant label written to the CSV.")
    parser.add_argument("--size", required=True, help="Instance size written to the CSV n column.")
    parser.add_argument("--seed", type=int, required=True, help="Clingo random seed.")
    parser.add_argument(
        "--setting",
        default="seed_only",
        help="Randomization setting label written to the CSV.",
    )
    parser.add_argument(
        "--clingo-option",
        action="append",
        default=[],
        metavar="ARG",
        help="Extra option passed to the JSON/statistics clingo run. Can be repeated.",
    )
    parser.add_argument("--semantics", default="native", help="Semantic label for logs and benchmark configs.")
    parser.add_argument("--csv", required=True, help="CSV file to append.")
    parser.add_argument("--models", type=int, default=DEFAULT_MODELS, help=f"Number of models requested. Default: {DEFAULT_MODELS}.")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help=f"Timeout in seconds. Default: {DEFAULT_TIMEOUT}.")
    parser.add_argument(
        "--memory-bytes",
        type=int,
        default=DEFAULT_MEMORY_BYTES,
        help=f"Address-space limit in bytes. Default: {DEFAULT_MEMORY_BYTES}.",
    )
    parser.add_argument(
        "-c",
        "--constant",
        action="append",
        default=[],
        metavar="NAME=VALUE",
        help="Constant passed to clingo. Can be repeated.",
    )
    parser.add_argument(
        "--domain-heuristic",
        action="store_true",
        help="Pass --heuristic=Domain to clingo.",
    )
    parser.add_argument(
        "--order",
        choices=["instance-first", "encoding-first"],
        default="instance-first",
        help="Order of input files passed to clingo. Default: instance-first.",
    )
    return parser.parse_args()


def main() -> int:
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    return run_benchmark(parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
