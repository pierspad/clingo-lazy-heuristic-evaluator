#!/usr/bin/env bash
# BSP benchmark iterator. The per-run execution and JSON stats parsing live in
# benchmark_runner.py.

set -euo pipefail

# ==============================================================================
# CONFIGURAZIONE BENCHMARK BSP
# Override rapido da shell, per esempio:
#   BSP_VARIANTS="gc_noheur gc ga ga_dyn la lc la_aux" ./benchmark_bsp.sh
# ==============================================================================
DEFAULT_TIMEOUT_SECONDS=180
DEFAULT_REPEATS=2
DEFAULT_N_START=10
DEFAULT_N_END=200
DEFAULT_N_STEP=10
DEFAULT_MEM_LIMIT_BYTES=$((10 * 1024 * 1024 * 1024))
DEFAULT_STOP_VARIANT_ON_LIMIT=1
DEFAULT_BSP_VARIANTS="ga_dyn ga gc_noheur gc la_aux la_co la lc"
# ==============================================================================

PYTHON_BIN="${PYTHON_BIN:-python3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TEST_ROOT}/.." && pwd)"
RUNNER="${SCRIPT_DIR}/benchmark_runner.py"
printf -v BENCHMARK_LAUNCH_COMMAND "%q " "$0" "$@"
BENCHMARK_LAUNCH_COMMAND="${BENCHMARK_LAUNCH_COMMAND% }"

CLINGO_MOD="${CLINGO_MOD:-}"
for candidate in \
    "${REPO_ROOT}/build/bin/clingo" \
    "${REPO_ROOT}/clingo-modified/build/bin/clingo"; do
    if [ -z "${CLINGO_MOD}" ] && [ -x "${candidate}" ]; then
        CLINGO_MOD="${candidate}"
    fi
done

if [ -z "${CLINGO_MOD}" ]; then
    echo "Errore: binario clingo modificato non trovato."
    exit 1
fi

if [ ! -x "${RUNNER}" ]; then
    echo "Errore: runner benchmark non trovato: ${RUNNER}"
    exit 1
fi

TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-${DEFAULT_TIMEOUT_SECONDS}}"
if [ -n "${MEM_LIMIT_BYTES:-}" ]; then
    MEM_LIMIT_BYTES="${MEM_LIMIT_BYTES}"
elif [ -n "${MEM_LIMIT_GB:-}" ]; then
    MEM_LIMIT_BYTES="$("${PYTHON_BIN}" -c 'import sys; print(int(float(sys.argv[1]) * 1024**3))' "${MEM_LIMIT_GB}")"
elif [ -n "${MEM_LIMIT_MB:-}" ]; then
    MEM_LIMIT_BYTES="$("${PYTHON_BIN}" -c 'import sys; print(int(float(sys.argv[1]) * 1024**2))' "${MEM_LIMIT_MB}")"
else
    MEM_LIMIT_BYTES="${DEFAULT_MEM_LIMIT_BYTES}"
fi

REPEATS="${REPEATS:-${DEFAULT_REPEATS}}"
N_START="${N_START:-${DEFAULT_N_START}}"
N_END="${N_END:-${DEFAULT_N_END}}"
N_STEP="${N_STEP:-${DEFAULT_N_STEP}}"
STOP_VARIANT_ON_LIMIT="${STOP_VARIANT_ON_LIMIT:-${DEFAULT_STOP_VARIANT_ON_LIMIT}}"

ENC_DIR="${TEST_ROOT}/encodings/BSP"
INSTANCE_RANGE="${TEST_ROOT}/instances/BSP_instances/BSP_range.lp"
RESULTS_DIR="${TEST_ROOT}/results"
CSV_FILE="${RESULTS_DIR}/bsp_results.csv"
METADATA_FILE="${RESULTS_DIR}/run_metadata.json"

declare -A VARIANT_FILES=(
    [gc_noheur]="${ENC_DIR}/BSP_gc_noheur.lp"
    [gc]="${ENC_DIR}/BSP_gc.lp"
    [ga]="${ENC_DIR}/BSP_ga.lp"
    [ga_dyn]="${ENC_DIR}/BSP_ga_dyn.lp"
    [la]="${ENC_DIR}/BSP_la.lp"
    [lc]="${ENC_DIR}/BSP_lc.lp"
    [la_aux]="${ENC_DIR}/BSP_la_aux.lp"
    [la_co]="${ENC_DIR}/BSP_la_co.lp"
)

declare -A VARIANT_SEMANTICS=(
    [gc_noheur]="clingo"
    [gc]="clingo"
    [ga]="alpha"
    [ga_dyn]="alpha"
    [la]="alpha"
    [lc]="clingo"
    [la_aux]="alpha"
    [la_co]="alpha"
)

write_run_metadata() {
    local metadata_file="$1"
    local variant_specs=()
    local variant
    for variant in "${ENABLED_VARIANTS[@]}"; do
        variant_specs+=("${variant}|${VARIANT_FILES[${variant}]}|${VARIANT_SEMANTICS[${variant}]}")
    done

    "${PYTHON_BIN}" - \
        "${metadata_file}" \
        "${REPO_ROOT}" \
        "${CLINGO_MOD}" \
        "${RUNNER}" \
        "${INSTANCE_RANGE}" \
        "${CSV_FILE}" \
        "${TIMEOUT_SECONDS}" \
        "${MEM_LIMIT_BYTES}" \
        "${REPEATS}" \
        "${N_START}" \
        "${N_END}" \
        "${N_STEP}" \
        "${STOP_VARIANT_ON_LIMIT}" \
        "${BENCHMARK_LAUNCH_COMMAND}" \
        "${PYTHON_BIN}" \
        "${variant_specs[@]}" <<'PY'
import datetime as dt
import json
import os
import platform
import shlex
import socket
import subprocess
import sys
from pathlib import Path

metadata_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
clingo_path = Path(sys.argv[3])
runner_path = Path(sys.argv[4])
instance_range = Path(sys.argv[5])
csv_file = Path(sys.argv[6])
timeout_seconds = int(sys.argv[7])
memory_bytes = int(sys.argv[8])
repeats = int(sys.argv[9])
n_start = int(sys.argv[10])
n_end = int(sys.argv[11])
n_step = int(sys.argv[12])
stop_variant_on_limit = sys.argv[13] == "1"
launcher_command = sys.argv[14]
python_bin = sys.argv[15]
variant_specs = sys.argv[16:]


def run_text(cmd, *, cwd=None):
    try:
        return subprocess.check_output(
            cmd,
            cwd=cwd,
            text=True,
            stderr=subprocess.STDOUT,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def first_line(text):
    return text.splitlines()[0] if text and text != "unknown" else text


def human_bytes(value):
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    amount = float(value)
    for unit in units:
        if amount < 1024 or unit == units[-1]:
            return f"{amount:.2f} {unit}"
        amount /= 1024


def read_os_release():
    path = Path("/etc/os-release")
    if not path.is_file():
        return {}
    data = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key] = value.strip().strip('"')
    return data


def read_cpu_model():
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.is_file():
        for line in cpuinfo.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.lower().startswith("model name"):
                return line.split(":", 1)[1].strip()
    return platform.processor() or "unknown"


def read_ram_bytes():
    meminfo = Path("/proc/meminfo")
    if meminfo.is_file():
        for line in meminfo.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("MemTotal:"):
                return int(line.split()[1]) * 1024
    if hasattr(os, "sysconf"):
        try:
            return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
        except (OSError, ValueError):
            pass
    return None


def parse_cmake_cache(cache_path):
    if not cache_path or not cache_path.is_file():
        return {}
    values = {}
    for line in cache_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line or line.startswith(("//", "#")) or ":" not in line or "=" not in line:
            continue
        key_type, value = line.split("=", 1)
        key = key_type.split(":", 1)[0]
        values[key] = value.strip()
    return values


def find_cmake_cache(binary_path):
    try:
        resolved = binary_path.resolve()
    except OSError:
        resolved = binary_path
    for parent in [resolved.parent, *resolved.parents]:
        candidate = parent / "CMakeCache.txt"
        if candidate.is_file():
            return candidate
    return None


cmake_cache_path = find_cmake_cache(clingo_path)
cmake_cache = parse_cmake_cache(cmake_cache_path)
compiler_path = (
    cmake_cache.get("CMAKE_CXX_COMPILER")
    or os.environ.get("CXX")
    or "c++"
)
compiler_version = first_line(run_text([compiler_path, "--version"]))
build_type = (
    cmake_cache.get("CMAKE_BUILD_TYPE")
    or os.environ.get("CMAKE_BUILD_TYPE")
    or "unknown"
)

variant_details = []
for spec in variant_specs:
    name, encoding, semantics = spec.split("|", 2)
    variant_details.append({
        "name": name,
        "encoding": encoding,
        "semantics": semantics,
    })

runner_template = [
    python_bin,
    str(runner_path),
    "--clingo", str(clingo_path),
    "--encoding", "<encoding_file>",
    "--instance", str(instance_range),
    "--variant", "<variant>",
    "--semantics", "<semantics>",
    "--size", "<N>",
    "--seed", "<seed>",
    "--csv", str(csv_file),
    "--constant", "n=<N>",
    "--models", "1",
    "--timeout", str(timeout_seconds),
    "--memory-bytes", str(memory_bytes),
    "--domain-heuristic",
]
clingo_json_template = [
    str(clingo_path),
    str(instance_range),
    "<encoding_file>",
    "-c", "n=<N>",
    "--heuristic=Domain",
    "--outf=2",
    "--stats=2",
    "--seed=<seed>",
    "-n", "1",
    f"--time-limit={timeout_seconds}",
]
clingo_text_template = [
    str(clingo_path),
    str(instance_range),
    "<encoding_file>",
    "-c", "n=<N>",
    "--heuristic=Domain",
    "--text",
]

ram_bytes = read_ram_bytes()
os_release = read_os_release()
git_status = run_text(["git", "-C", str(repo_root), "status", "--short"])

metadata = {
    "commit_hash": run_text(["git", "-C", str(repo_root), "rev-parse", "HEAD"]),
    "git_dirty": bool(git_status and git_status != "unknown"),
    "benchmark_datetime": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
    "hostname": socket.gethostname(),
    "cpu": {
        "model": read_cpu_model(),
        "logical_cores": os.cpu_count(),
    },
    "ram": {
        "total_bytes": ram_bytes,
        "total_human": human_bytes(ram_bytes) if ram_bytes is not None else "unknown",
    },
    "os": {
        "platform": platform.platform(),
        "pretty_name": os_release.get("PRETTY_NAME", "unknown"),
    },
    "compiler": {
        "path": compiler_path,
        "version": compiler_version,
    },
    "build_type": build_type,
    "clingo_binary": str(clingo_path),
    "exact_command": launcher_command,
    "commands": {
        "benchmark_launcher": launcher_command,
        "runner_template": shlex.join(runner_template),
        "clingo_json_template": shlex.join(clingo_json_template),
        "clingo_text_template": shlex.join(clingo_text_template),
    },
    "timeout_seconds": timeout_seconds,
    "memory_limit": {
        "bytes": memory_bytes,
        "human": human_bytes(memory_bytes),
    },
    "repeats": repeats,
    "n_range": {
        "start": n_start,
        "end": n_end,
        "step": n_step,
    },
    "stop_variant_on_limit": stop_variant_on_limit,
    "active_variants": [variant["name"] for variant in variant_details],
    "variant_details": variant_details,
}
if cmake_cache_path:
    metadata["cmake_cache"] = str(cmake_cache_path)

metadata_path.parent.mkdir(parents=True, exist_ok=True)
metadata_path.write_text(
    json.dumps(metadata, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
}

read -r -a ACTIVE_VARIANTS <<< "${BSP_VARIANTS:-${DEFAULT_BSP_VARIANTS}}"

if [ ! -f "${INSTANCE_RANGE}" ]; then
    echo "Errore: file istanza BSP non trovato: ${INSTANCE_RANGE}"
    exit 1
fi

ENABLED_VARIANTS=()
for variant in "${ACTIVE_VARIANTS[@]}"; do
    file="${VARIANT_FILES[${variant}]:-}"
    if [ -z "${file}" ]; then
        echo "Errore: variante BSP sconosciuta '${variant}'."
        echo "Varianti valide: ${!VARIANT_FILES[*]}"
        exit 1
    fi
    if [ -f "${file}" ]; then
        ENABLED_VARIANTS+=("${variant}")
    else
        echo "Avviso: salto variante '${variant}' perche' il file '${file}' non esiste."
    fi
done

if [ "${#ENABLED_VARIANTS[@]}" -eq 0 ]; then
    echo "Errore: nessuna variante BSP attiva con file esistente."
    exit 1
fi

mkdir -p "${RESULTS_DIR}"
rm -f "${CSV_FILE}"
write_run_metadata "${METADATA_FILE}"

echo "Varianti BSP attive: ${ENABLED_VARIANTS[*]}"
MEM_LIMIT_GB="$("${PYTHON_BIN}" -c 'import sys; print(f"{int(sys.argv[1]) / (1024**3):.2f}")' "${MEM_LIMIT_BYTES}")"
echo "Parametri: timeout=${TIMEOUT_SECONDS}s repeats=${REPEATS} n=${N_START}..${N_END} step=${N_STEP} mem=${MEM_LIMIT_GB} GB"
if [ "${STOP_VARIANT_ON_LIMIT}" = "1" ]; then
    echo "Stop per variante su limite memoria/timeout: attivo"
else
    echo "Stop per variante su limite memoria/timeout: disattivo"
fi
echo "Risultati: ${CSV_FILE}"
echo "Metadata run: ${METADATA_FILE}"

planned_runs=$(( ((N_END - N_START) / N_STEP + 1) * ${#ENABLED_VARIANTS[@]} * REPEATS ))
current_run=0
declare -A VARIANT_STOPPED_BY_LIMIT=()
declare -A VARIANT_LIMIT_N=()
declare -A VARIANT_LIMIT_REASON=()
for variant in "${ENABLED_VARIANTS[@]}"; do
    VARIANT_STOPPED_BY_LIMIT["${variant}"]=0
done

for n in $(seq "${N_START}" "${N_STEP}" "${N_END}"); do
    echo ""
    echo "=== N=${n} ==="

    for variant in "${ENABLED_VARIANTS[@]}"; do
        if [ "${STOP_VARIANT_ON_LIMIT}" = "1" ] && [ "${VARIANT_STOPPED_BY_LIMIT[${variant}]}" = "1" ]; then
            echo "--- ${variant}: salto N=${n}; limite superato a N=${VARIANT_LIMIT_N[${variant}]} ---"
            continue
        fi

        for seed in $(seq 1 "${REPEATS}"); do
            current_run=$((current_run + 1))
            echo "--- ${variant} (run ${current_run}/${planned_runs}, seed ${seed}) ---"
            if "${PYTHON_BIN}" "${RUNNER}" \
                --clingo "${CLINGO_MOD}" \
                --encoding "${VARIANT_FILES[${variant}]}" \
                --instance "${INSTANCE_RANGE}" \
                --variant "${variant}" \
                --semantics "${VARIANT_SEMANTICS[${variant}]}" \
                --size "${n}" \
                --seed "${seed}" \
                --csv "${CSV_FILE}" \
                --constant "n=${n}" \
                --models 1 \
                --timeout "${TIMEOUT_SECONDS}" \
                --memory-bytes "${MEM_LIMIT_BYTES}" \
                --domain-heuristic; then
                rc=0
            else
                rc=$?
            fi

            if [ "${rc}" -eq 75 -o "${rc}" -eq 124 ] && [ "${STOP_VARIANT_ON_LIMIT}" = "1" ]; then
                VARIANT_STOPPED_BY_LIMIT["${variant}"]=1
                VARIANT_LIMIT_N["${variant}"]="${n}"
                if [ "${rc}" -eq 75 ]; then
                    VARIANT_LIMIT_REASON["${variant}"]="OOM"
                else
                    VARIANT_LIMIT_REASON["${variant}"]="TIMEOUT"
                fi
                echo "--- ${variant}: limite memoria/timeout raggiunto a N=${n}; salto i run e valori successivi per questa variante ---"
                break
            fi
        done
    done
done

echo ""
echo "Benchmark BSP completato. ${current_run} esecuzioni totali."
if [ "${STOP_VARIANT_ON_LIMIT}" = "1" ]; then
    > "${RESULTS_DIR}/bsp_failures.txt"
    for variant in "${ENABLED_VARIANTS[@]}"; do
        if [ "${VARIANT_STOPPED_BY_LIMIT[${variant}]}" = "1" ]; then
            fn="${VARIANT_LIMIT_N[${variant}]}"
            fr="${VARIANT_LIMIT_REASON[${variant}]}"
            echo -e "${fn}\t${variant}\t${fr}" >> "${RESULTS_DIR}/bsp_failures.txt"
        fi
    done
    if [ -s "${RESULTS_DIR}/bsp_failures.txt" ]; then
        echo "=== REPORT FALLIMENTI BSP (ordinato per N crescente) ==="
        sort -n "${RESULTS_DIR}/bsp_failures.txt" | while read -r fn fv fr; do
            echo " - Variante '${fv}' ha fallito a N=${fn} causa: ${fr}"
        done
        echo "========================================================"
    else
        echo "=== Nessun fallimento registrato in BSP! ==="
    fi
fi
echo "Risultati salvati in: ${CSV_FILE}"
