#!/usr/bin/env bash
# benchmark_pup.sh
# Benchmark per il problema PUP (Paired Unit Placement).
# Testa 4 encoding con clingo standard:
#
#   pup          — encoding dichiarativo   (__PUP.asp)
#   pup_heur     — encoding con euristiche statiche (__PUP_heur.asp)
#   pup_double   — encoding con aggregati dinamici  (__PUP_double.asp)
#   pup_doublev  — encoding variante                (__PUP_double_variant.asp)
#
# Istanze usate:
#   pup, pup_heur, pup_double  → PUP_instances/Double/
#   pup_doublev                → PUP_instances/DoubleVariant/
#
# Ogni combinazione (instance, variant) viene eseguita REPEATS volte con seed diversi.
# Tutte le esecuzioni usano --heuristic=Domain --time-limit=600.
# Salva i risultati in:
#   ./test-results/pup_double_results.csv    (pup, pup_heur, pup_double su Double/)
#   ./test-results/pup_doublev_results.csv   (pup_doublev su DoubleVariant/)

set -euo pipefail

# ============================================================================
# CONFIGURAZIONE
# ============================================================================

CLINGO="clingo"

# Encoding files
FILE_PUP="__PUP.asp"
FILE_PUP_HEUR="__PUP_heur.asp"
FILE_PUP_DOUBLE="__PUP_double.asp"
FILE_PUP_DOUBLEV="__PUP_double_variant.asp"

# Instance directories
INSTANCES_DOUBLE="PUP_instances/Double"
INSTANCES_DOUBLEV="PUP_instances/DoubleVariant"

# Numero di ripetizioni per ogni (instance, variant) con seed diversi
REPEATS=3

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
# FUNZIONE: estrae la dimensione N dal nome file (es. "double-30.asp" → 30)
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
    echo "${instance_size},${variant},${seed},${solving_s},${total_s},${choices},${conflicts},${restarts},${rules},${variables},${memory_mb}" >> "${csv_file}"
}

# ============================================================================
# FUNZIONE: benchmark su una lista di istanze con un encoding dato
# ============================================================================

run_encoding_on_instances() {
    local variant_name="$1"
    local encoding="$2"
    local instance_dir="$3"
    local csv_file="$4"
    local total_runs="$5"
    local current_run_ref="$6"   # nome della variabile (passata per riferimento via nameref)

    local -n _current_run="${current_run_ref}"

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

    IFS=$'\n' instances=($(for f in "${instances[@]}"; do
        size=$(extract_instance_size "$(basename "$f")")
        echo "${size} ${f}"
    done | sort -n | awk '{print $2}'))
    unset IFS

    for inst in "${instances[@]}"; do
        local basename_inst
        basename_inst="$(basename "${inst}")"
        local instance_size
        instance_size="$(extract_instance_size "${basename_inst}")"

        echo ""
        echo "  [${variant_name}] Istanza: ${basename_inst} (N=${instance_size})"

        for seed in $(seq 1 "${REPEATS}"); do
            _current_run=$((_current_run + 1))
            echo "--- ${variant_name} (run ${_current_run}/${total_runs}) ---"
            run_stats "${instance_size}" "${variant_name}" "${seed}" "${csv_file}" \
                ${CLINGO} "${inst}" "${encoding}" "-n" "1" \
                "--heuristic=Domain" "--time-limit=600"
        done
    done
}

# ============================================================================
# CALCOLO TOTALE ESECUZIONI
# ============================================================================

n_double=$(find "${INSTANCES_DOUBLE}" -name "*.asp" | wc -l)
n_doublev=$(find "${INSTANCES_DOUBLEV}" -name "*.asp" | wc -l)

# 3 encoding su Double, 1 encoding su DoubleVariant
total_runs=$(( (n_double * 3 + n_doublev * 1) * REPEATS ))
current_run=0

# ============================================================================
# CSV: istanze Double (pup, pup_heur, pup_double)
# ============================================================================

CSV_DOUBLE="${TIMINGS_DIR}/pup_double_results.csv"
echo "n,variant,seed,solving_s,total_s,choices,conflicts,restarts,rules,variables,memory_mb" > "${CSV_DOUBLE}"

echo ""
echo "================================================================"
echo "  BENCHMARK PUP — Istanze Double"
echo "  Directory: ${INSTANCES_DOUBLE}"
echo "================================================================"

echo ""
echo "--- Encoding: ${FILE_PUP} ---"
run_encoding_on_instances "pup"        "${FILE_PUP}"        "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run

echo ""
echo "--- Encoding: ${FILE_PUP_HEUR} ---"
run_encoding_on_instances "pup_heur"   "${FILE_PUP_HEUR}"   "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run

echo ""
echo "--- Encoding: ${FILE_PUP_DOUBLE} ---"
run_encoding_on_instances "pup_double" "${FILE_PUP_DOUBLE}" "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run

# ============================================================================
# CSV: istanze DoubleVariant (pup_doublev)
# ============================================================================

CSV_DOUBLEV="${TIMINGS_DIR}/pup_doublev_results.csv"
echo "n,variant,seed,solving_s,total_s,choices,conflicts,restarts,rules,variables,memory_mb" > "${CSV_DOUBLEV}"

echo ""
echo "================================================================"
echo "  BENCHMARK PUP — Istanze DoubleVariant"
echo "  Directory: ${INSTANCES_DOUBLEV}"
echo "================================================================"

echo ""
echo "--- Encoding: ${FILE_PUP_DOUBLEV} ---"
run_encoding_on_instances "pup_doublev" "${FILE_PUP_DOUBLEV}" "${INSTANCES_DOUBLEV}" "${CSV_DOUBLEV}" "${total_runs}" current_run

# ============================================================================
# FINE
# ============================================================================

echo ""
echo "================================================================"
echo "  Benchmark PUP completato. ${current_run} esecuzioni totali."
echo "  Risultati Double:       ${CSV_DOUBLE}"
echo "  Risultati DoubleVariant: ${CSV_DOUBLEV}"
echo "================================================================"
