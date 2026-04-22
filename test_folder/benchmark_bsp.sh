#!/usr/bin/env bash
# benchmark_bsp.sh
# Benchmark per il problema BSP (Balanced Sum Partition).
# Testa 3 configurazioni con clingo standard:
#   std      — encoding dichiarativo puro  (__BSP.lp)
#   lg       — lazy grounding              (_BSP_lg.lp)
#   colg     — lazy grounding + vincolo ottimizzato (_BSP_colg.lp)
#
# Ogni combinazione (N, variant) viene eseguita REPEATS volte con seed diversi.
# Tutte le esecuzioni usano --heuristic=Domain --time-limit=600.
# Salva i risultati in ./test-results/bsp_results.csv

set -euo pipefail

# ============================================================================
# CONFIGURAZIONE
# ============================================================================

CLINGO="clingo"

# Encoding files
FILE_STD="__BSP.lp"
FILE_LG="_BSP_lg.lp"
FILE_COLG="_BSP_colg.lp"

# Range file (in BSP_instances/)
FILE_RANGE="BSP_instances/__.BSP_range.lp"

N_START=10
N_END=200
N_STEP=10

# Numero di ripetizioni per ogni (N, variant) con seed diversi
REPEATS=3

TIMINGS_DIR="./test-results"
CSV_FILE="${TIMINGS_DIR}/bsp_results.csv"

mkdir -p "${TIMINGS_DIR}"

# ============================================================================
# INTESTAZIONE CSV
# ============================================================================

echo "n,variant,seed,solving_s,total_s,choices,conflicts,restarts,rules,variables,memory_mb" > "${CSV_FILE}"

# Cerchiamo GNU time per la memoria
TIME_BIN="$(command -v time || true)"
if ! file "${TIME_BIN}" 2>/dev/null | grep -q "ELF"; then
    for candidate in /usr/bin/time /usr/local/bin/time; do
        if [ -x "${candidate}" ]; then
            TIME_BIN="${candidate}"
            break
        fi
    done
fi

# ============================================================================
# FUNZIONE: esegui un singolo test e parsa le statistiche
# ============================================================================

run_stats() {
    local n="$1"
    local variant="$2"
    local seed="$3"
    shift 3
    local cmd=("$@")

    echo "  [seed=${seed}] ${cmd[*]}"

    local output
    output="$( { "${TIME_BIN}" -v "${cmd[@]}" --stats=2 --seed="${seed}" ; } 2>&1 )" || true

    local solving_s
    solving_s="$(echo "${output}" | grep -oP '(?<=Solving: )[0-9.]+(?=s)' | head -1 || echo "NA")"
    if [ -z "${solving_s}" ]; then solving_s="NA"; fi

    local total_s
    total_s="$(echo "${output}" | grep -P '^Time\s+:' | grep -oP '[0-9.]+(?=s)' | head -1 || echo "NA")"
    if [ -z "${total_s}" ]; then total_s="NA"; fi

    local choices
    choices="$(echo "${output}" | grep -P '^Choices\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${choices}" ]; then choices="NA"; fi

    local conflicts
    conflicts="$(echo "${output}" | grep -P '^Conflicts\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${conflicts}" ]; then conflicts="NA"; fi

    local restarts
    restarts="$(echo "${output}" | grep -P '^Restarts\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${restarts}" ]; then restarts="NA"; fi

    local rules
    rules="$(echo "${output}" | grep -P '^Rules\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${rules}" ]; then rules="NA"; fi

    local variables
    variables="$(echo "${output}" | grep -P '^Variables\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${variables}" ]; then variables="NA"; fi

    local rss_kb memory_mb
    rss_kb="$(echo "${output}" | grep -oP '(?<=Maximum resident set size \(kbytes\): )\d+' || echo "")"
    if [ -z "${rss_kb}" ]; then
        memory_mb="NA"
    else
        memory_mb="$(echo "${rss_kb}" | awk '{printf "%.4f", $1/1024}')"
    fi

    echo "    solving=${solving_s}s total=${total_s}s choices=${choices} conflicts=${conflicts} restarts=${restarts} rules=${rules} vars=${variables} mem=${memory_mb}MB"
    echo "${n},${variant},${seed},${solving_s},${total_s},${choices},${conflicts},${restarts},${rules},${variables},${memory_mb}" >> "${CSV_FILE}"
}

# ============================================================================
# LOOP PRINCIPALE
# ============================================================================

total_runs=$(( ((N_END - N_START) / N_STEP + 1) * 3 * REPEATS ))
current_run=0

for n in $(seq "${N_START}" "${N_STEP}" "${N_END}"); do
    echo ""
    echo "=== N=${n} ==="

    # 1) Encoding standard dichiarativo
    for seed in $(seq 1 "${REPEATS}"); do
        current_run=$((current_run + 1))
        echo "--- std (run ${current_run}/${total_runs}) ---"
        run_stats "${n}" "std" "${seed}" \
            ${CLINGO} "${FILE_RANGE}" "${FILE_STD}" "-c" "n=${n}" "-n" "1" \
            "--heuristic=Domain" "--time-limit=600"
    done

    # 2) Lazy grounding
    for seed in $(seq 1 "${REPEATS}"); do
        current_run=$((current_run + 1))
        echo "--- lg (run ${current_run}/${total_runs}) ---"
        run_stats "${n}" "lg" "${seed}" \
            ${CLINGO} "${FILE_RANGE}" "${FILE_LG}" "-n" "1" "-c" "n=${n}" \
            "--heuristic=Domain" "--time-limit=600"
    done

    # 3) Lazy grounding + vincolo ottimizzato
    for seed in $(seq 1 "${REPEATS}"); do
        current_run=$((current_run + 1))
        echo "--- colg (run ${current_run}/${total_runs}) ---"
        run_stats "${n}" "colg" "${seed}" \
            ${CLINGO} "${FILE_RANGE}" "${FILE_COLG}" "-n" "1" "-c" "n=${n}" \
            "--heuristic=Domain" "--time-limit=600"
    done
done

echo ""
echo "Benchmark BSP completato. ${current_run} esecuzioni totali."
echo "Risultati salvati in: ${CSV_FILE}"
