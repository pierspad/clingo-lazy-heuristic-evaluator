#!/usr/bin/env bash
# benchmark_bsp.sh
# Benchmark per il problema BSP (Balanced Sum Partition).
# Testa 4 configurazioni:
#   std      — Clingo standard, encoding dichiarativo (no --heuristic=Domain)
#   h-clingo — Clingo standard, encoding con euristiche + --heuristic=Domain
#   mod      — Clingo modificato, lazy grounding
#   mod_opt  — Clingo modificato, lazy grounding + vincolo ottimizzato
#
# Ogni combinazione (N, variant) viene eseguita REPEATS volte con seed diversi.
# Salva i risultati in ./test-results/bsp_results.csv

set -euo pipefail

# ============================================================================
# CONFIGURAZIONE
# ============================================================================

CLINGO_STD="clingo"
CLINGO_MOD="/home/ribben/Desktop/clingo-lazy-heuristics/clingo-modified/build/bin/clingo"

# Encoding files
FILE_STD="__BSP.lp"                             # encoding dichiarativo con euristiche (usato come base)
FILE_MOD="_BSP_lg.lp"                           # lazy grounding
FILE_MOD_OPT="_BSP_colg.lp"                     # lazy grounding + vincolo ottimizzato

# Range file (ora in BSP_instances/)
FILE_RANGE="BSP_instances/__.BSP_range.lp"

N_START=10
N_END=200
N_STEP=10

# Numero di ripetizioni per ogni (N, variant) con seed diversi
REPEATS=3

# Timeout in secondi (10 minuti come nel paper)
TIME_LIMIT=600

TIMINGS_DIR="./test-results"
CSV_FILE="${TIMINGS_DIR}/bsp_results.csv"

mkdir -p "${TIMINGS_DIR}"

# ============================================================================
# INTESTAZIONE CSV
# ============================================================================
# Colonne:
#   n           - dimensione del problema
#   variant     - "std", "h-clingo", "mod" o "mod_opt"
#   seed        - seed usato per questa esecuzione
#   solving_s   - tempo di solving netto (dal solver CDNL)
#   total_s     - tempo totale (grounding + solving)
#   choices     - numero di scelte (decisioni) del solver
#   conflicts   - numero di conflitti
#   restarts    - numero di restart
#   rules       - numero di regole ground (dimensione grounding)
#   variables   - numero di variabili proposizionali
#   memory_mb   - memoria RSS massima (via /usr/bin/time, fallback)
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

    # Eseguiamo con GNU time per avere la memoria RSS
    local output
    output="$( { "${TIME_BIN}" -v "${cmd[@]}" --stats=2 --seed="${seed}" --time-limit="${TIME_LIMIT}" ; } 2>&1 )" || true

    # --- Parsing del tempo di solving (dal report interno di Clingo) ---
    local solving_s
    solving_s="$(echo "${output}" | grep -oP '(?<=Solving: )[0-9.]+(?=s)' | head -1 || echo "NA")"
    if [ -z "${solving_s}" ]; then solving_s="NA"; fi

    # --- Parsing del tempo totale (dal report interno di Clingo) ---
    local total_s
    total_s="$(echo "${output}" | grep -P '^Time\s+:' | grep -oP '[0-9.]+(?=s)' | head -1 || echo "NA")"
    if [ -z "${total_s}" ]; then total_s="NA"; fi

    # --- Choices ---
    local choices
    choices="$(echo "${output}" | grep -P '^Choices\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${choices}" ]; then choices="NA"; fi

    # --- Conflicts ---
    local conflicts
    conflicts="$(echo "${output}" | grep -P '^Conflicts\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${conflicts}" ]; then conflicts="NA"; fi

    # --- Restarts ---
    local restarts
    restarts="$(echo "${output}" | grep -P '^Restarts\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${restarts}" ]; then restarts="NA"; fi

    # --- Rules (grounding size) ---
    local rules
    rules="$(echo "${output}" | grep -P '^Rules\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${rules}" ]; then rules="NA"; fi

    # --- Variables ---
    local variables
    variables="$(echo "${output}" | grep -P '^Variables\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${variables}" ]; then variables="NA"; fi

    # --- Memoria RSS (da GNU time) ---
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

total_runs=$(( ((N_END - N_START) / N_STEP + 1) * 4 * REPEATS ))
current_run=0

for n in $(seq "${N_START}" "${N_STEP}" "${N_END}"); do
    echo ""
    echo "=== N=${n} ==="

    # 1) Baseline: Clingo standard senza --heuristic=Domain (euristiche ignorate)
    for seed in $(seq 1 "${REPEATS}"); do
        current_run=$((current_run + 1))
        echo "--- std (run ${current_run}/${total_runs}) ---"
        run_stats "${n}" "std" "${seed}" \
            ${CLINGO_STD} "${FILE_RANGE}" "${FILE_STD}" "-c" "n=${n}" "-n" "1"
    done

    # 2) h-Clingo: Clingo standard con --heuristic=Domain (euristiche statiche)
    for seed in $(seq 1 "${REPEATS}"); do
        current_run=$((current_run + 1))
        echo "--- h-clingo (run ${current_run}/${total_runs}) ---"
        run_stats "${n}" "h-clingo" "${seed}" \
            ${CLINGO_STD} "${FILE_RANGE}" "${FILE_STD}" "-c" "n=${n}" "-n" "1" "--heuristic=Domain"
    done

    # 3) Clingo modificato con lazy grounding
    for seed in $(seq 1 "${REPEATS}"); do
        current_run=$((current_run + 1))
        echo "--- mod (run ${current_run}/${total_runs}) ---"
        run_stats "${n}" "mod" "${seed}" \
            ${CLINGO_MOD} "${FILE_RANGE}" "${FILE_MOD}" "-n" "1" "-c" "n=${n}"
    done

    # 4) Clingo modificato con lazy grounding + vincolo ottimizzato
    for seed in $(seq 1 "${REPEATS}"); do
        current_run=$((current_run + 1))
        echo "--- mod_opt (run ${current_run}/${total_runs}) ---"
        run_stats "${n}" "mod_opt" "${seed}" \
            ${CLINGO_MOD} "${FILE_RANGE}" "${FILE_MOD_OPT}" "-n" "1" "-c" "n=${n}"
    done
done

echo ""
echo "Benchmark BSP completato. ${current_run} esecuzioni totali."
echo "Risultati salvati in: ${CSV_FILE}"
