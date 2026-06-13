#!/usr/bin/env bash
set -euo pipefail

capture_overrides() {
    local name target
    for name in "$@"; do
        if [ "${!name+x}" ]; then
            target="__OVERRIDE_${name}"
            printf -v "${target}" "%s" "${!name}"
        fi
    done
}

apply_overrides() {
    local name source
    for name in "$@"; do
        source="__OVERRIDE_${name}"
        if [ "${!source+x}" ]; then
            printf -v "${name}" "%s" "${!source}"
        fi
    done
}

BSP_CONFIG_VARS=(
    BSP_TIMEOUT_SECONDS
    BSP_REPEATS
    BSP_N_START
    BSP_N_END
    BSP_N_STEP
    BSP_STOP_VARIANT_ON_LIMIT
    BSP_USE_SEED
    BSP_MEM_LIMIT_BYTES
    BSP_MEM_LIMIT_MB
    BSP_MEM_LIMIT_GB
    BSP_VARIANTS
    BSP_RANDOM_SETTINGS
    BSP_CLINGO_EXTRA_ARGS
    BSP_RESULTS_CSV
    BSP_METADATA_FILE
    BSP_FAILURES_FILE
)
capture_overrides "${BSP_CONFIG_VARS[@]}"

BSP_TIMEOUT_SECONDS=240
BSP_REPEATS=2
BSP_N_START=10
BSP_N_END=200
BSP_N_STEP=10
BSP_STOP_VARIANT_ON_LIMIT=1
BSP_USE_SEED=0

BSP_MEM_LIMIT_BYTES=
BSP_MEM_LIMIT_MB=
BSP_MEM_LIMIT_GB=10

BSP_VARIANTS="ga_weak ga gc_noheur gc la_aux la_co la lc"
#BSP_VARIANTS="ga gc_noheur gc la lc"
BSP_RANDOM_SETTINGS="default:"
BSP_CLINGO_EXTRA_ARGS=

BSP_RESULTS_CSV="test_folder/results/bsp_results.csv"
BSP_METADATA_FILE="test_folder/results/run_metadata.json"
BSP_FAILURES_FILE="test_folder/results/bsp_failures.txt"

apply_overrides "${BSP_CONFIG_VARS[@]}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TEST_ROOT}/.." && pwd)"
RUNNER="${SCRIPT_DIR}/benchmark_runner.py"
printf -v BENCHMARK_LAUNCH_COMMAND "%q " "$0" "$@"
BENCHMARK_LAUNCH_COMMAND="${BENCHMARK_LAUNCH_COMMAND% }"

repo_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "${REPO_ROOT}" "$1" ;;
    esac
}

command_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        */*) repo_path "$1" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

require_positive_int() {
    local name="$1"
    local value="$2"
    if ! [[ "${value}" =~ ^[0-9]+$ ]] || [ "${value}" -lt 1 ]; then
        echo "Errore: ${name} deve essere un intero positivo, ricevuto '${value}'." >&2
        exit 1
    fi
}

require_bool01() {
    local name="$1"
    local value="$2"
    if [ "${value}" != "0" ] && [ "${value}" != "1" ]; then
        echo "Errore: ${name} deve valere 0 oppure 1, ricevuto '${value}'." >&2
        exit 1
    fi
}

CLINGO_MOD="$(command_path "${CLINGO_MOD:-}")"
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
if [[ "${CLINGO_MOD}" == */* ]]; then
    if [ ! -x "${CLINGO_MOD}" ]; then
        echo "Errore: binario clingo non eseguibile: ${CLINGO_MOD}"
        exit 1
    fi
elif ! command -v "${CLINGO_MOD}" >/dev/null 2>&1; then
    echo "Errore: binario clingo non trovato nel PATH: ${CLINGO_MOD}"
    exit 1
fi

if [ ! -x "${RUNNER}" ]; then
    echo "Errore: runner benchmark non trovato: ${RUNNER}"
    exit 1
fi

TIMEOUT_SECONDS="${BSP_TIMEOUT_SECONDS}"
if [ -n "${BSP_MEM_LIMIT_BYTES:-}" ]; then
    MEM_LIMIT_BYTES="${BSP_MEM_LIMIT_BYTES}"
elif [ -n "${BSP_MEM_LIMIT_MB:-}" ]; then
    MEM_LIMIT_BYTES="$("${PYTHON_BIN}" -c 'import sys; print(int(float(sys.argv[1]) * 1024**2))' "${BSP_MEM_LIMIT_MB}")"
elif [ -n "${BSP_MEM_LIMIT_GB:-}" ]; then
    MEM_LIMIT_BYTES="$("${PYTHON_BIN}" -c 'import sys; print(int(float(sys.argv[1]) * 1024**3))' "${BSP_MEM_LIMIT_GB}")"
else
    MEM_LIMIT_BYTES=$((10 * 1024 * 1024 * 1024))
fi

REPEATS="${BSP_REPEATS}"
N_START="${BSP_N_START}"
N_END="${BSP_N_END}"
N_STEP="${BSP_N_STEP}"
STOP_VARIANT_ON_LIMIT="${BSP_STOP_VARIANT_ON_LIMIT}"
BSP_USE_SEED="${BSP_USE_SEED}"
BSP_RANDOM_SETTINGS_EFFECTIVE="${BSP_RANDOM_SETTINGS}"
BSP_RANDOM_SETTINGS="${BSP_RANDOM_SETTINGS_EFFECTIVE}"
CLINGO_EXTRA_ARGS="${BSP_CLINGO_EXTRA_ARGS}"

require_positive_int "TIMEOUT_SECONDS" "${TIMEOUT_SECONDS}"
require_positive_int "MEM_LIMIT_BYTES" "${MEM_LIMIT_BYTES}"
require_positive_int "REPEATS" "${REPEATS}"
require_positive_int "N_START" "${N_START}"
require_positive_int "N_END" "${N_END}"
require_positive_int "N_STEP" "${N_STEP}"
require_bool01 "STOP_VARIANT_ON_LIMIT" "${STOP_VARIANT_ON_LIMIT}"
require_bool01 "BSP_USE_SEED" "${BSP_USE_SEED}"
if [ "${N_END}" -lt "${N_START}" ]; then
    echo "Errore: N_END (${N_END}) deve essere maggiore o uguale a N_START (${N_START})." >&2
    exit 1
fi

ENC_DIR="${TEST_ROOT}/encodings/BSP"
INSTANCE_RANGE="${TEST_ROOT}/instances/BSP_instances/BSP_range.lp"
RESULTS_DIR="${TEST_ROOT}/results"
CSV_FILE="$(repo_path "${BSP_RESULTS_CSV}")"
METADATA_FILE="$(repo_path "${BSP_METADATA_FILE}")"
FAILURES_FILE="$(repo_path "${BSP_FAILURES_FILE}")"
export LAZY_HEURISTIC_BACKEND="prolog"

export PYTHON_BIN
export CLINGO_MOD
export BSP_TIMEOUT_SECONDS="${TIMEOUT_SECONDS}"
export BSP_REPEATS="${REPEATS}"
export BSP_N_START="${N_START}"
export BSP_N_END="${N_END}"
export BSP_N_STEP="${N_STEP}"
export BSP_STOP_VARIANT_ON_LIMIT="${STOP_VARIANT_ON_LIMIT}"
export BSP_USE_SEED
export BSP_MEM_LIMIT_BYTES="${MEM_LIMIT_BYTES}"
export TIMEOUT_SECONDS
export MEM_LIMIT_BYTES
export REPEATS
export N_START
export N_END
export N_STEP
export STOP_VARIANT_ON_LIMIT
export BSP_VARIANTS
export BSP_RANDOM_SETTINGS
export BSP_RANDOM_SETTINGS_EFFECTIVE
export BSP_CLINGO_EXTRA_ARGS="${CLINGO_EXTRA_ARGS}"
export CLINGO_EXTRA_ARGS
export BSP_RESULTS_CSV="${CSV_FILE}"
export BSP_METADATA_FILE="${METADATA_FILE}"
export BSP_FAILURES_FILE="${FAILURES_FILE}"

declare -A VARIANT_FILES=(
    [gc_noheur]="${ENC_DIR}/BSP_gc_noheur.lp"
    [gc]="${ENC_DIR}/BSP_gc.lp"
    [ga]="${ENC_DIR}/BSP_ga.lp"
    [ga_weak]="${ENC_DIR}/BSP_ga_weak.lp"
    [la]="${ENC_DIR}/BSP_la.lp"
    [lc]="${ENC_DIR}/BSP_lc.lp"
    [la_aux]="${ENC_DIR}/BSP_la_aux.lp"
    [la_co]="${ENC_DIR}/BSP_la_co.lp"
)

declare -A VARIANT_SEMANTICS=(
    [gc_noheur]="clingo"
    [gc]="clingo"
    [ga]="alpha"
    [ga_weak]="alpha"
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

use_seed = os.environ.get("BSP_USE_SEED", "0") == "1"
runner_template = [
    python_bin,
    str(runner_path),
    "--clingo", str(clingo_path),
    "--encoding", "<encoding_file>",
    "--instance", str(instance_range),
    "--variant", "<variant>",
    "--semantics", "<semantics>",
    "--size", "<N>",
]
if use_seed:
    runner_template.extend(["--seed", "<seed>"])
runner_template.extend([
    "--setting", "<setting>",
    "--csv", str(csv_file),
    "--constant", "n=<N>",
    "--models", "1",
    "--timeout", str(timeout_seconds),
    "--memory-bytes", str(memory_bytes),
    "--domain-heuristic",
    "<setting-specific --clingo-option>",
    "<global --clingo-option>",
])
clingo_json_template = [
    str(clingo_path),
    str(instance_range),
    "<encoding_file>",
    "-c", "n=<N>",
    "--heuristic=Domain",
    "--outf=2",
    "--stats=2",
]
if use_seed:
    clingo_json_template.append("--seed=<seed>")
clingo_json_template.extend([
    "-n", "1",
    f"--time-limit={timeout_seconds}",
    "<setting-specific clingo options>",
    "<CLINGO_EXTRA_ARGS>",
])
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
    "settings": os.environ.get("BSP_RANDOM_SETTINGS_EFFECTIVE", "default:"),
    "random_settings": os.environ.get("BSP_RANDOM_SETTINGS_EFFECTIVE", "default:"),
    "use_seed": use_seed,
    "clingo_extra_args": os.environ.get("CLINGO_EXTRA_ARGS", ""),
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

read -r -a ACTIVE_VARIANTS <<< "${BSP_VARIANTS}"
read -r -a ACTIVE_SETTING_SPECS <<< "${BSP_RANDOM_SETTINGS_EFFECTIVE}"

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

SETTING_NAMES=()
SETTING_EXTRA_ARGS=()
for setting_spec in "${ACTIVE_SETTING_SPECS[@]}"; do
    setting_name="${setting_spec%%:*}"
    if [ -z "${setting_name}" ]; then
        echo "Errore: setting BSP non valido: '${setting_spec}'."
        exit 1
    fi
    if [[ "${setting_spec}" == *":"* ]]; then
        setting_args="${setting_spec#*:}"
    else
        setting_args=""
    fi
    SETTING_NAMES+=("${setting_name}")
    SETTING_EXTRA_ARGS+=("${setting_args}")
done

if [ "${#SETTING_NAMES[@]}" -eq 0 ]; then
    echo "Errore: nessun setting BSP attivo."
    exit 1
fi

mkdir -p "${RESULTS_DIR}"
mkdir -p "$(dirname "${CSV_FILE}")" "$(dirname "${METADATA_FILE}")" "$(dirname "${FAILURES_FILE}")"
rm -f "${CSV_FILE}"
write_run_metadata "${METADATA_FILE}"

echo "Varianti BSP attive: ${ENABLED_VARIANTS[*]}"
echo "Setting BSP attivi: ${SETTING_NAMES[*]}"
MEM_LIMIT_GB="$("${PYTHON_BIN}" -c 'import sys; print(f"{int(sys.argv[1]) / (1024**3):.2f}")' "${MEM_LIMIT_BYTES}")"
echo "Parametri: timeout=${TIMEOUT_SECONDS}s repeats=${REPEATS} n=${N_START}..${N_END} step=${N_STEP} mem=${MEM_LIMIT_GB} GB"
if [ "${BSP_USE_SEED}" = "1" ]; then
    echo "Seed Clingo: attivo (--seed=<repeat>)"
else
    echo "Seed Clingo: disattivo (nessun --seed)"
fi
if [ -n "${CLINGO_EXTRA_ARGS:-}" ]; then
    echo "Opzioni Clingo extra globali: ${CLINGO_EXTRA_ARGS}"
fi
if [ "${STOP_VARIANT_ON_LIMIT}" = "1" ]; then
    echo "Stop per variante su limite memoria/timeout: attivo"
else
    echo "Stop per variante su limite memoria/timeout: disattivo"
fi
echo "Risultati: ${CSV_FILE}"
echo "Metadata run: ${METADATA_FILE}"

planned_runs=$(( ((N_END - N_START) / N_STEP + 1) * ${#ENABLED_VARIANTS[@]} * REPEATS * ${#SETTING_NAMES[@]} ))
current_run=0
declare -A VARIANT_STOPPED_BY_LIMIT=()
declare -A VARIANT_LIMIT_N=()
declare -A VARIANT_LIMIT_REASON=()
for setting in "${SETTING_NAMES[@]}"; do
    for variant in "${ENABLED_VARIANTS[@]}"; do
        VARIANT_STOPPED_BY_LIMIT["${setting}:${variant}"]=0
    done
done

for setting_index in "${!SETTING_NAMES[@]}"; do
    setting="${SETTING_NAMES[${setting_index}]}"
    setting_args="${SETTING_EXTRA_ARGS[${setting_index}]}"
    read -r -a SETTING_CLINGO_ARGS <<< "${setting_args}"
    read -r -a GLOBAL_CLINGO_ARGS <<< "${CLINGO_EXTRA_ARGS:-}"

    echo ""
    echo "=== Setting ${setting} ==="
    if [ -n "${setting_args}" ]; then
        echo "Opzioni setting: ${setting_args}"
    fi

    for n in $(seq "${N_START}" "${N_STEP}" "${N_END}"); do
        echo ""
        echo "=== N=${n} ==="

        for variant in "${ENABLED_VARIANTS[@]}"; do
            variant_key="${setting}:${variant}"
            if [ "${STOP_VARIANT_ON_LIMIT}" = "1" ] && [ "${VARIANT_STOPPED_BY_LIMIT[${variant_key}]}" = "1" ]; then
                echo "--- ${variant} (${setting}): salto N=${n}; limite superato a N=${VARIANT_LIMIT_N[${variant_key}]} ---"
                continue
            fi

            for seed in $(seq 1 "${REPEATS}"); do
                runner_seed_option=()
                seed_label="none"
                if [ "${BSP_USE_SEED}" = "1" ]; then
                    runner_seed_option=(--seed "${seed}")
                    seed_label="${seed}"
                fi
                runner_extra_options=()
                for opt in "${SETTING_CLINGO_ARGS[@]}"; do
                    if [ -n "${opt}" ]; then
                        runner_extra_options+=("--clingo-option=${opt}")
                    fi
                done
                for opt in "${GLOBAL_CLINGO_ARGS[@]}"; do
                    if [ -n "${opt}" ]; then
                        runner_extra_options+=("--clingo-option=${opt}")
                    fi
                done

                current_run=$((current_run + 1))
                echo "--- ${variant} (run ${current_run}/${planned_runs}, setting ${setting}, seed ${seed_label}) ---"
                if "${PYTHON_BIN}" "${RUNNER}" \
                    --clingo "${CLINGO_MOD}" \
                    --encoding "${VARIANT_FILES[${variant}]}" \
                    --instance "${INSTANCE_RANGE}" \
                    --variant "${variant}" \
                    --semantics "${VARIANT_SEMANTICS[${variant}]}" \
                    --size "${n}" \
                    "${runner_seed_option[@]}" \
                    --setting "${setting}" \
                    --csv "${CSV_FILE}" \
                    --constant "n=${n}" \
                    --models 1 \
                    --timeout "${TIMEOUT_SECONDS}" \
                    --memory-bytes "${MEM_LIMIT_BYTES}" \
                    --domain-heuristic \
                    "${runner_extra_options[@]}"; then
                    rc=0
                else
                    rc=$?
                fi

                if [ "${rc}" -eq 75 -o "${rc}" -eq 124 ] && [ "${STOP_VARIANT_ON_LIMIT}" = "1" ]; then
                    VARIANT_STOPPED_BY_LIMIT["${variant_key}"]=1
                    VARIANT_LIMIT_N["${variant_key}"]="${n}"
                    if [ "${rc}" -eq 75 ]; then
                        VARIANT_LIMIT_REASON["${variant_key}"]="OOM"
                    else
                        VARIANT_LIMIT_REASON["${variant_key}"]="TIMEOUT"
                    fi
                    echo "--- ${variant} (${setting}): limite memoria/timeout raggiunto a N=${n}; salto i run e valori successivi per questa variante/setting ---"
                    break
                fi
            done
        done
    done
done

echo ""
echo "Benchmark BSP completato. ${current_run} esecuzioni totali."
"${PYTHON_BIN}" - "${CSV_FILE}" "${FAILURES_FILE}" <<'PY'
import csv
import sys
from pathlib import Path

csv_path = Path(sys.argv[1])
failures_path = Path(sys.argv[2])
rows = []
if csv_path.is_file():
    with csv_path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row.get("status") and row.get("status") != "ok":
                rows.append(row)

def sort_key(row):
    try:
        n = int(row.get("n", "0"))
    except ValueError:
        n = 0
    return (
        n,
        row.get("setting", ""),
        row.get("variant", ""),
        row.get("seed", ""),
    )

rows.sort(key=sort_key)
failures_path.parent.mkdir(parents=True, exist_ok=True)
with failures_path.open("w", encoding="utf-8") as handle:
    for row in rows:
        handle.write(
            "\t".join(
                [
                    row.get("n", "NA"),
                    row.get("setting", "NA"),
                    row.get("variant", "NA"),
                    row.get("failure_reason", "NA") or "NA",
                    row.get("status", "NA"),
                ]
            )
            + "\n"
        )
PY
if [ -s "${FAILURES_FILE}" ]; then
    echo "=== REPORT FALLIMENTI BSP (ordinato per N crescente) ==="
    while IFS=$'\t' read -r fn fs fv fr fst; do
        echo " - N=${fn} setting=${fs} variant=${fv} status=${fst} failure_reason=${fr}"
    done < "${FAILURES_FILE}"
    echo "========================================================"
else
    echo "=== Nessun fallimento registrato in BSP! ==="
fi
echo "Risultati salvati in: ${CSV_FILE}"
