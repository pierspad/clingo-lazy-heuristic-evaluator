#!/usr/bin/env bash
# benchmark_pup.sh
# Benchmark per il problema PUP (Paired Unit Placement).
# Testa 3 configurazioni su due famiglie di istanze (Double e DoubleV):
#
#   clingo      — Clingo standard, encoding dichiarativo (baseline, no euristiche)
#   h-clingo    — Clingo standard, encoding con euristiche topologiche + --heuristic=Domain
#   alpha       — Clingo modificato, encoding Alpha con aggregati dinamici + --heuristic=Domain
#
# Per la famiglia Double usa __PUP_double.asp come encoding alpha.
# Per la famiglia DoubleV usa __PUP_double_variant.asp come encoding alpha.
#
# Ogni combinazione (instance, variant) viene eseguita REPEATS volte con seed diversi.
# Salva i risultati in:
#   ./test-results/pup_double_results.csv
#   ./test-results/pup_doublev_results.csv

set -euo pipefail

# ============================================================================
# CONFIGURAZIONE
# ============================================================================

CLINGO_STD="clingo"
CLINGO_MOD="/home/ribben/Desktop/clingo-lazy-heuristics/clingo-modified/build/bin/clingo"

# Encoding files
FILE_BASELINE="__PUP.asp"                          # encoding dichiarativo (baseline)
FILE_HCLINGO="__PUP_heur.asp"                      # encoding con euristiche topologiche statiche
FILE_ALPHA_DOUBLE="__PUP_double.asp"               # encoding Alpha per Double
FILE_ALPHA_DOUBLEV="__PUP_double_variant.asp"      # encoding Alpha per DoubleV

# Instance directories
INSTANCES_DOUBLE="PUP_instances/Double"
INSTANCES_DOUBLEV="PUP_instances/DoubleV"

# Numero di ripetizioni per ogni (instance, variant) con seed diversi
REPEATS=3

# Timeout in secondi (10 minuti come nel paper)
TIME_LIMIT=600

TIMINGS_DIR="./test-results"

mkdir -p "${TIMINGS_DIR}"

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
# FUNZIONE: estrae la dimensione N dal nome dell'istanza (es. "double-30.asp" → 30)
# ============================================================================

extract_instance_size() {
    local filename="$1"
    echo "${filename}" | grep -oP '\d+' | tail -1
}

# ============================================================================
# FUNZIONE: esegui un singolo test e parsa le statistiche
# ============================================================================

run_stats() {
    local instance_size="$1"
    local variant="$2"
    local seed="$3"
    local csv_file="$4"
    shift 4
    local cmd=("$@")

    echo "  [seed=${seed}] ${cmd[*]}"

    # Eseguiamo con GNU time per avere la memoria RSS
    local output
    output="$( { "${TIME_BIN}" -v "${cmd[@]}" --stats=2 --seed="${seed}" --time-limit="${TIME_LIMIT}" ; } 2>&1 )" || true

    # --- Parsing del tempo di solving ---
    local solving_s
    solving_s="$(echo "${output}" | grep -oP '(?<=Solving: )[0-9.]+(?=s)' | head -1 || echo "NA")"
    if [ -z "${solving_s}" ]; then solving_s="NA"; fi

    # --- Parsing del tempo totale ---
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

    # --- Rules ---
    local rules
    rules="$(echo "${output}" | grep -P '^Rules\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${rules}" ]; then rules="NA"; fi

    # --- Variables ---
    local variables
    variables="$(echo "${output}" | grep -P '^Variables\s+:' | grep -oP '\d+' | head -1 || echo "NA")"
    if [ -z "${variables}" ]; then variables="NA"; fi

    # --- Memoria RSS ---
    local rss_kb memory_mb
    rss_kb="$(echo "${output}" | grep -oP '(?<=Maximum resident set size \(kbytes\): )\d+' || echo "")"
    if [ -z "${rss_kb}" ]; then
        memory_mb="NA"
    else
        memory_mb="$(echo "${rss_kb}" | awk '{printf "%.4f", $1/1024}')"
    fi

    echo "    solving=${solving_s}s total=${total_s}s choices=${choices} conflicts=${conflicts} restarts=${restarts} rules=${rules} vars=${variables} mem=${memory_mb}MB"
    echo "${instance_size},${variant},${seed},${solving_s},${total_s},${choices},${conflicts},${restarts},${rules},${variables},${memory_mb}" >> "${csv_file}"
}

# ============================================================================
# FUNZIONE: benchmark su una famiglia di istanze
# ============================================================================

run_family() {
    local family_name="$1"
    local instance_dir="$2"
    local alpha_encoding="$3"
    local csv_file="$4"

    echo ""
    echo "================================================================"
    echo "  Famiglia: ${family_name}"
    echo "  Istanze:  ${instance_dir}"
    echo "  Alpha:    ${alpha_encoding}"
    echo "  CSV:      ${csv_file}"
    echo "================================================================"

    # Intestazione CSV
    echo "n,variant,seed,solving_s,total_s,choices,conflicts,restarts,rules,variables,memory_mb" > "${csv_file}"

    # Raccogli e ordina le istanze per dimensione
    local instances=()
    for inst in "${instance_dir}"/*.asp; do
        [ -f "${inst}" ] || continue
        instances+=("${inst}")
    done

    if [ ${#instances[@]} -eq 0 ]; then
        echo "  ATTENZIONE: nessuna istanza trovata in ${instance_dir}"
        return
    fi

    # Ordina le istanze per dimensione numerica
    IFS=$'\n' instances=($(for f in "${instances[@]}"; do
        size=$(extract_instance_size "$(basename "$f")")
        echo "${size} ${f}"
    done | sort -n | awk '{print $2}'))
    unset IFS

    local total_instances=${#instances[@]}
    local total_runs=$(( total_instances * 3 * REPEATS ))
    local current_run=0

    for inst in "${instances[@]}"; do
        local basename_inst
        basename_inst="$(basename "${inst}")"
        local instance_size
        instance_size="$(extract_instance_size "${basename_inst}")"

        echo ""
        echo "=== ${family_name} - Istanza: ${basename_inst} (N=${instance_size}) ==="

        # 1) Baseline: Clingo standard, encoding dichiarativo, no euristiche
        for seed in $(seq 1 "${REPEATS}"); do
            current_run=$((current_run + 1))
            echo "--- clingo (run ${current_run}/${total_runs}) ---"
            run_stats "${instance_size}" "clingo" "${seed}" "${csv_file}" \
                ${CLINGO_STD} "${inst}" "${FILE_BASELINE}" "-n" "1"
        done

        # 2) h-Clingo: Clingo standard, euristiche topologiche statiche
        for seed in $(seq 1 "${REPEATS}"); do
            current_run=$((current_run + 1))
            echo "--- h-clingo (run ${current_run}/${total_runs}) ---"
            run_stats "${instance_size}" "h-clingo" "${seed}" "${csv_file}" \
                ${CLINGO_STD} "${inst}" "${FILE_HCLINGO}" "-n" "1" "--heuristic=Domain"
        done

        # 3) Alpha: Clingo modificato, aggregati dinamici
        for seed in $(seq 1 "${REPEATS}"); do
            current_run=$((current_run + 1))
            echo "--- alpha (run ${current_run}/${total_runs}) ---"
            run_stats "${instance_size}" "alpha" "${seed}" "${csv_file}" \
                ${CLINGO_MOD} "${inst}" "${alpha_encoding}" "-n" "1" "--heuristic=Domain"
        done
    done

    echo ""
    echo "Benchmark ${family_name} completato. ${current_run} esecuzioni."
}

# ============================================================================
# ESECUZIONE
# ============================================================================

echo "================================================================"
echo "  BENCHMARK PUP (Paired Unit Placement)"
echo "  $(date)"
echo "================================================================"

# Famiglia Double
run_family "Double" "${INSTANCES_DOUBLE}" "${FILE_ALPHA_DOUBLE}" \
    "${TIMINGS_DIR}/pup_double_results.csv"

# Famiglia DoubleV
run_family "DoubleV" "${INSTANCES_DOUBLEV}" "${FILE_ALPHA_DOUBLEV}" \
    "${TIMINGS_DIR}/pup_doublev_results.csv"

echo ""
echo "================================================================"
echo "  Benchmark PUP completato."
echo "  Risultati Double:  ${TIMINGS_DIR}/pup_double_results.csv"
echo "  Risultati DoubleV: ${TIMINGS_DIR}/pup_doublev_results.csv"
echo "================================================================"
