#!/usr/bin/env bash
# benchmark.sh
# Esegue i test e salva i risultati in ./test-results/results.csv

set -euo pipefail

CLINGO_STD="clingo"
CLINGO_MOD="/home/ribben/Desktop/clingo-lazy-heuristics/clingo-modified/build/bin/clingo"
FILE_STD="__BSP.lp"
FILE_MOD="_2_lazy_ground.lp"
FILE_RANGE="__.common_range.lp"

N_START=10
N_END=100
N_STEP=5

TIMINGS_DIR="./test-results"
CSV_FILE="${TIMINGS_DIR}/results.csv"

mkdir -p "${TIMINGS_DIR}"

# Scrittura intestazione CSV
echo "n,variant,elapsed_s,memory_mb" > "${CSV_FILE}"

# Cerchiamo GNU time
TIME_BIN="$(command -v time || true)"
if file "${TIME_BIN}" 2>/dev/null | grep -q "ELF"; then
    :
else
    for candidate in /usr/bin/time /usr/local/bin/time; do
        if [ -x "${candidate}" ]; then
            TIME_BIN="${candidate}"
            break
        fi
    done
fi

run_timed() {
    local n="$1"
    local variant="$2"
    shift 2
    local cmd=("$@")

    echo ">>> N=${n}  variant=${variant}  cmd: ${cmd[*]}"

    local time_output
    time_output="$( { "${TIME_BIN}" -v "${cmd[@]}" ; } 2>&1 )" || true

    local elapsed_raw elapsed_s
    elapsed_raw="$(echo "${time_output}" | grep -oP '(?<=Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): )[\d:.]+' || echo "")"
    if [ -z "${elapsed_raw}" ]; then
        elapsed_s="NA"
    else
        elapsed_s="$(echo "${elapsed_raw}" | awk -F: '{
            if (NF==3) { print ($1*3600 + $2*60 + $3) }
            else if (NF==2) { print ($1*60 + $2) }
            else { print $1 }
        }')"
    fi

    local rss_kb memory_mb
    rss_kb="$(echo "${time_output}" | grep -oP '(?<=Maximum resident set size \(kbytes\): )\d+' || echo "")"
    if [ -z "${rss_kb}" ]; then
        memory_mb="NA"
    else
        memory_mb="$(echo "${rss_kb}" | awk '{printf "%.4f", $1/1024}')"
    fi

    echo "    elapsed=${elapsed_s}s  memory=${memory_mb}MB"
    echo "${n},${variant},${elapsed_s},${memory_mb}" >> "${CSV_FILE}"
}

for n in $(seq "${N_START}" "${N_STEP}" "${N_END}"); do
    echo ""
    echo "=== N=${n} ==="

    run_timed "${n}" "std" \
        ${CLINGO_STD} "${FILE_RANGE}" "${FILE_STD}" "-c" "n=${n}"

    run_timed "${n}" "mod" \
        ${CLINGO_MOD} "${FILE_RANGE}" "${FILE_MOD}" "-n" "1" "-c" "n=${n}"
done

echo ""
echo "Benchmark completato. Risultati salvati in: ${CSV_FILE}"
