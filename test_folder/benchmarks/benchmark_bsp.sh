#!/usr/bin/env bash
# BSP benchmark iterator. The per-run execution and JSON stats parsing live in
# benchmark_runner.py.

set -euo pipefail

# ==============================================================================
# CONFIGURAZIONE BENCHMARK BSP
# Override rapido da shell, per esempio:
#   BSP_VARIANTS="gc_noheur gc ga la lc la_aux" ./benchmark_bsp.sh
#   BSP_RANDOM_SETTINGS="seed_only: rand_freq_0_01:--rand-freq=0.01" REPEATS=3 ./benchmark_bsp.sh
#   CLINGO_EXTRA_ARGS="--init-watches=rnd" ./benchmark_bsp.sh
# ==============================================================================
DEFAULT_TIMEOUT_SECONDS=180
DEFAULT_REPEATS=2
DEFAULT_N_START=10
DEFAULT_N_END=200
DEFAULT_N_STEP=10
DEFAULT_MEM_LIMIT_BYTES=$((10 * 1024 * 1024 * 1024))
DEFAULT_STOP_VARIANT_ON_LIMIT=1
DEFAULT_BSP_VARIANTS="ga gc_noheur gc la_aux la_co la lc"
DEFAULT_BSP_RANDOM_SETTINGS="seed_only:"
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
BSP_RANDOM_SETTINGS_EFFECTIVE="${BSP_RANDOM_SETTINGS:-${DEFAULT_BSP_RANDOM_SETTINGS}}"
export BSP_RANDOM_SETTINGS_EFFECTIVE

ENC_DIR="${TEST_ROOT}/encodings/BSP"
INSTANCE_RANGE="${TEST_ROOT}/instances/BSP_instances/BSP_range.lp"
RESULTS_DIR="${TEST_ROOT}/results"
CSV_FILE="${BSP_RESULTS_CSV:-${RESULTS_DIR}/bsp_results.csv}"
METADATA_FILE="${BSP_METADATA_FILE:-${RESULTS_DIR}/run_metadata.json}"
FAILURES_FILE="${BSP_FAILURES_FILE:-${RESULTS_DIR}/bsp_failures.txt}"

declare -A VARIANT_FILES=(
    [gc_noheur]="${ENC_DIR}/BSP_gc_noheur.lp"
    [gc]="${ENC_DIR}/BSP_gc.lp"
    [ga]="${ENC_DIR}/BSP_ga.lp"
    [ga_weak]="${ENC_DIR}/BDP_ga_weak.lp"
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
    "--setting", "<setting>",
    "--csv", str(csv_file),
    "--constant", "n=<N>",
    "--models", "1",
    "--timeout", str(timeout_seconds),
    "--memory-bytes", str(memory_bytes),
    "--domain-heuristic",
    "<setting-specific --clingo-option>",
    "<global --clingo-option>",
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
    "<setting-specific clingo options>",
    "<CLINGO_EXTRA_ARGS>",
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
    "random_settings": os.environ.get("BSP_RANDOM_SETTINGS_EFFECTIVE", "seed_only:"),
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

read -r -a ACTIVE_VARIANTS <<< "${BSP_VARIANTS:-${DEFAULT_BSP_VARIANTS}}"
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
        echo "Errore: setting random BSP non valido: '${setting_spec}'."
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
    echo "Errore: nessun setting random BSP attivo."
    exit 1
fi

mkdir -p "${RESULTS_DIR}"
mkdir -p "$(dirname "${CSV_FILE}")" "$(dirname "${METADATA_FILE}")" "$(dirname "${FAILURES_FILE}")"
rm -f "${CSV_FILE}"
write_run_metadata "${METADATA_FILE}"

echo "Varianti BSP attive: ${ENABLED_VARIANTS[*]}"
echo "Setting random attivi: ${SETTING_NAMES[*]}"
MEM_LIMIT_GB="$("${PYTHON_BIN}" -c 'import sys; print(f"{int(sys.argv[1]) / (1024**3):.2f}")' "${MEM_LIMIT_BYTES}")"
echo "Parametri: timeout=${TIMEOUT_SECONDS}s repeats=${REPEATS} n=${N_START}..${N_END} step=${N_STEP} mem=${MEM_LIMIT_GB} GB"
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
                echo "--- ${variant} (run ${current_run}/${planned_runs}, setting ${setting}, seed ${seed}) ---"
                if "${PYTHON_BIN}" "${RUNNER}" \
                    --clingo "${CLINGO_MOD}" \
                    --encoding "${VARIANT_FILES[${variant}]}" \
                    --instance "${INSTANCE_RANGE}" \
                    --variant "${variant}" \
                    --semantics "${VARIANT_SEMANTICS[${variant}]}" \
                    --size "${n}" \
                    --seed "${seed}" \
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
if [ "${STOP_VARIANT_ON_LIMIT}" = "1" ]; then
    > "${FAILURES_FILE}"
    for setting in "${SETTING_NAMES[@]}"; do
        for variant in "${ENABLED_VARIANTS[@]}"; do
            variant_key="${setting}:${variant}"
            if [ "${VARIANT_STOPPED_BY_LIMIT[${variant_key}]}" = "1" ]; then
                fn="${VARIANT_LIMIT_N[${variant_key}]}"
                fr="${VARIANT_LIMIT_REASON[${variant_key}]}"
                echo -e "${fn}\t${setting}\t${variant}\t${fr}" >> "${FAILURES_FILE}"
            fi
        done
    done
    if [ -s "${FAILURES_FILE}" ]; then
        echo "=== REPORT FALLIMENTI BSP (ordinato per N crescente) ==="
        sort -n "${FAILURES_FILE}" | while read -r fn fs fv fr; do
            echo " - Variante '${fv}' (${fs}) ha fallito a N=${fn} causa: ${fr}"
        done
        echo "========================================================"
    else
        echo "=== Nessun fallimento registrato in BSP! ==="
    fi
fi
echo "Risultati salvati in: ${CSV_FILE}"
