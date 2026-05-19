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

TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"
if [ -n "${MEM_LIMIT_BYTES:-}" ]; then
    MEM_LIMIT_BYTES="${MEM_LIMIT_BYTES}"
elif [ -n "${MEM_LIMIT_GB:-}" ]; then
    MEM_LIMIT_BYTES="$(python3 -c 'import sys; print(int(float(sys.argv[1]) * 1024**3))' "${MEM_LIMIT_GB}")"
elif [ -n "${MEM_LIMIT_MB:-}" ]; then
    MEM_LIMIT_BYTES="$(python3 -c 'import sys; print(int(float(sys.argv[1]) * 1024**2))' "${MEM_LIMIT_MB}")"
else
    MEM_LIMIT_BYTES="$((8 * 1024 * 1024 * 1024))"
fi

REPEATS="${REPEATS:-1}"
N_START="${N_START:-10}"
N_END="${N_END:-50}"
N_STEP="${N_STEP:-10}"
STOP_VARIANT_ON_MEMORY="${STOP_VARIANT_ON_MEMORY:-1}"

ENC_DIR="${TEST_ROOT}/encodings/BSP"
INSTANCE_RANGE="${TEST_ROOT}/instances/BSP_instances/BSP_range.lp"
RESULTS_DIR="${TEST_ROOT}/results"
CSV_FILE="${RESULTS_DIR}/bsp_results.csv"

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

DEFAULT_VARIANTS=(gc_noheur gc ga la lc la_aux)
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
MEM_LIMIT_GB="$(python3 -c 'import sys; print(f"{int(sys.argv[1]) / (1024**3):.2f}")' "${MEM_LIMIT_BYTES}")"
echo "Parametri: timeout=${TIMEOUT_SECONDS}s repeats=${REPEATS} n=${N_START}..${N_END} step=${N_STEP} mem=${MEM_LIMIT_GB} GB"
if [ "${STOP_VARIANT_ON_MEMORY}" = "1" ]; then
    echo "Stop per variante su limite memoria: attivo"
else
    echo "Stop per variante su limite memoria: disattivo"
fi
echo "Risultati: ${CSV_FILE}"

planned_runs=$(( ((N_END - N_START) / N_STEP + 1) * ${#ENABLED_VARIANTS[@]} * REPEATS ))
current_run=0
declare -A VARIANT_STOPPED_BY_MEMORY=()
declare -A VARIANT_MEMORY_N=()
for variant in "${ENABLED_VARIANTS[@]}"; do
    VARIANT_STOPPED_BY_MEMORY["${variant}"]=0
done

for n in $(seq "${N_START}" "${N_STEP}" "${N_END}"); do
    echo ""
    echo "=== N=${n} ==="

    for variant in "${ENABLED_VARIANTS[@]}"; do
        if [ "${STOP_VARIANT_ON_MEMORY}" = "1" ] && [ "${VARIANT_STOPPED_BY_MEMORY[${variant}]}" = "1" ]; then
            echo "--- ${variant}: salto N=${n}; limite memoria gia' raggiunto a N=${VARIANT_MEMORY_N[${variant}]} ---"
            continue
        fi

        for seed in $(seq 1 "${REPEATS}"); do
            current_run=$((current_run + 1))
            echo "--- ${variant} (run ${current_run}/${planned_runs}, seed ${seed}) ---"
            if python3 "${RUNNER}" \
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

            if [ "${rc}" -eq 75 ] && [ "${STOP_VARIANT_ON_MEMORY}" = "1" ]; then
                VARIANT_STOPPED_BY_MEMORY["${variant}"]=1
                VARIANT_MEMORY_N["${variant}"]="${n}"
                echo "--- ${variant}: limite memoria raggiunto a N=${n}; salto i valori successivi per questa variante ---"
                break
            fi
        done
    done
done

echo ""
echo "Benchmark BSP completato. ${current_run} esecuzioni totali."
if [ "${STOP_VARIANT_ON_MEMORY}" = "1" ]; then
    for variant in "${ENABLED_VARIANTS[@]}"; do
        if [ "${VARIANT_STOPPED_BY_MEMORY[${variant}]}" = "1" ]; then
            echo "Variante ${variant}: fermata dopo hit di memoria a N=${VARIANT_MEMORY_N[${variant}]}."
        fi
    done
fi
echo "Risultati salvati in: ${CSV_FILE}"
