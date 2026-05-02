#!/usr/bin/env bash
# BSP benchmark iterator. The per-run execution and JSON stats parsing live in
# benchmark_runner.py.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TEST_ROOT}/.." && pwd)"
RUNNER="${SCRIPT_DIR}/benchmark_runner.py"

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

TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"
MEM_LIMIT_BYTES="${MEM_LIMIT_BYTES:-$((32 * 1024 * 1024 * 1024))}"
REPEATS="${REPEATS:-3}"
N_START="${N_START:-10}"
N_END="${N_END:-70}"
N_STEP="${N_STEP:-10}"

ENC_DIR="${TEST_ROOT}/encodings/BSP"
INSTANCE_RANGE="${TEST_ROOT}/instances/BSP_instances/BSP_range.lp"
RESULTS_DIR="${TEST_ROOT}/results"
CSV_FILE="${RESULTS_DIR}/bsp_results.csv"

declare -A VARIANT_FILES=(
    [gc]="${ENC_DIR}/BSP_gc.lp"
    [gc_aux]="${ENC_DIR}/BSP_gc_aux.lp"
    [ga]="${ENC_DIR}/BSP_ga.lp"
    [la]="${ENC_DIR}/BSP_la.lp"
    [lc]="${ENC_DIR}/BSP_lc.lp"
    [la_aux]="${ENC_DIR}/BSP_la_aux.lp"
    [la_co]="${ENC_DIR}/BSP_la_co.lp"
)

declare -A VARIANT_SEMANTICS=(
    [gc]="clingo"
    [gc_aux]="clingo"
    [ga]="alpha"
    [la]="alpha"
    [lc]="clingo"
    [la_aux]="alpha"
    [la_co]="alpha"
)

DEFAULT_VARIANTS=(gc gc_aux ga la lc la_aux)
read -r -a ACTIVE_VARIANTS <<< "${BSP_VARIANTS:-${DEFAULT_VARIANTS[*]}}"

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

echo "Varianti BSP attive: ${ENABLED_VARIANTS[*]}"
echo "Risultati: ${CSV_FILE}"

total_runs=$(( ((N_END - N_START) / N_STEP + 1) * ${#ENABLED_VARIANTS[@]} * REPEATS ))
current_run=0

for n in $(seq "${N_START}" "${N_STEP}" "${N_END}"); do
    echo ""
    echo "=== N=${n} ==="

    for variant in "${ENABLED_VARIANTS[@]}"; do
        for seed in $(seq 1 "${REPEATS}"); do
            current_run=$((current_run + 1))
            echo "--- ${variant} (run ${current_run}/${total_runs}) ---"
            python3 "${RUNNER}" \
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
                --domain-heuristic
        done
    done
done

echo ""
echo "Benchmark BSP completato. ${current_run} esecuzioni totali."
echo "Risultati salvati in: ${CSV_FILE}"
