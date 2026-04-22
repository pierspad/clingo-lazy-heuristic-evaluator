#!/usr/bin/env bash
# benchmark_pup.sh
# Benchmark per il problema PUP (Paired Unit Placement).
# Testa 4 encoding con il binario clingo modificato:
#
#   pup          — encoding dichiarativo   (__PUP.lp)
#   pup_heur     — encoding con euristiche statiche (__PUP_heur.lp)
#   pup_double   — encoding lazy convertito         (_PUP_double_lg.lp)
#   pup_doublev  — encoding lazy convertito variante (_PUP_double_variant_lg.lp)
#
# Istanze usate (stessa baseline per entrambe le famiglie):
#   Double/         → pup, pup_heur, pup_double
#   DoubleVariant/  → pup, pup_heur, pup_doublev
#
# Ogni combinazione (instance, variant) viene eseguita REPEATS volte con seed diversi.
# Le varianti euristiche usano --heuristic=Domain; baseline pup usa euristica default.
# Ogni run è protetta da timeout esterno a 600s e limite memoria 32GiB (se prlimit è disponibile).
# Salva i risultati in:
#   ./test-results/pup_double_results.csv    (pup, pup_heur, pup_double su Double/)
#   ./test-results/pup_doublev_results.csv   (pup, pup_heur, pup_doublev su DoubleVariant/)

set -euo pipefail

# ============================================================================
# CONFIGURAZIONE
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLINGO_MOD=""

for candidate in \
    "${REPO_ROOT}/build/bin/clingo" \
    "${REPO_ROOT}/clingo-modified/build/bin/clingo"; do
    if [ -x "${candidate}" ]; then
        CLINGO_MOD="${candidate}"
        break
    fi
done

TIMEOUT_SECONDS=600
MEM_LIMIT_BYTES=$((32 * 1024 * 1024 * 1024))

CONVERTER="${SCRIPT_DIR}/asp_heuristic_converter.py"

# Encoding files
FILE_PUP="__PUP.lp"
FILE_PUP_HEUR="__PUP_heur.lp"
FILE_PUP_DOUBLE_SRC="__PUP_double.lp"
FILE_PUP_DOUBLEV_SRC="__PUP_double_variant.lp"
FILE_PUP_DOUBLE="_PUP_double_lg.lp"
FILE_PUP_DOUBLEV="_PUP_double_variant_lg.lp"

# Instance directories
INSTANCES_DOUBLE="PUP_instances/Double"
INSTANCES_DOUBLEV="PUP_instances/DoubleVariant"

# Numero di ripetizioni per ogni (instance, variant) con seed diversi
REPEATS=3

TIMINGS_DIR="./test-results"

if [ -z "${CLINGO_MOD}" ]; then
    echo "Errore: binario clingo modificato non trovato. Percorsi provati:"
    echo "  - ${REPO_ROOT}/build/bin/clingo"
    echo "  - ${REPO_ROOT}/clingo-modified/build/bin/clingo"
    exit 1
fi

if [ ! -f "${CONVERTER}" ]; then
    echo "Errore: convertitore non trovato: ${CONVERTER}"
    exit 1
fi

cd "${SCRIPT_DIR}"

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
# PREPARAZIONE: genera encoding lazy per gli aggregati dinamici
# ============================================================================

generate_lazy_encodings() {
    echo ""
    echo "Genero encoding lazy con ${CONVERTER}..."
    python3 "${CONVERTER}" "${FILE_PUP_DOUBLE_SRC}" -o "${FILE_PUP_DOUBLE}"
    python3 "${CONVERTER}" "${FILE_PUP_DOUBLEV_SRC}" -o "${FILE_PUP_DOUBLEV}"
}

# ============================================================================
# FUNZIONE: estrae la dimensione N dal nome file (es. "double-30.lp" → 30)
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
    if command -v prlimit >/dev/null 2>&1; then
        output="$( { "${TIME_BIN}" -v prlimit --as="${MEM_LIMIT_BYTES}" -- timeout "${TIMEOUT_SECONDS}" "${cmd[@]}" --stats=2 --seed="${seed}" ; } 2>&1 )" || true
    else
        output="$( { "${TIME_BIN}" -v timeout "${TIMEOUT_SECONDS}" "${cmd[@]}" --stats=2 --seed="${seed}" ; } 2>&1 )" || true
    fi

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
    local use_domain="$7"

    local -n _current_run="${current_run_ref}"

    # Raccogli e ordina le istanze per dimensione
    local instances=()
    for inst in "${instance_dir}"/*.lp; do
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
            local cmd=("${CLINGO_MOD}" "${inst}" "${encoding}" "-n" "1" "--time-limit=600")
            if [ "${use_domain}" = "yes" ]; then
                cmd+=("--heuristic=Domain")
            fi
            run_stats "${instance_size}" "${variant_name}" "${seed}" "${csv_file}" "${cmd[@]}"
        done
    done
}

# ============================================================================
# CALCOLO TOTALE ESECUZIONI
# ============================================================================

n_double=$(find "${INSTANCES_DOUBLE}" -name "*.lp" | wc -l)
n_doublev=$(find "${INSTANCES_DOUBLEV}" -name "*.lp" | wc -l)

# 3 encoding su Double, 3 encoding su DoubleVariant
total_runs=$(( (n_double * 3 + n_doublev * 3) * REPEATS ))
current_run=0

generate_lazy_encodings

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
run_encoding_on_instances "pup"        "${FILE_PUP}"        "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run "no"

echo ""
echo "--- Encoding: ${FILE_PUP_HEUR} ---"
run_encoding_on_instances "pup_heur"   "${FILE_PUP_HEUR}"   "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run "yes"

echo ""
echo "--- Encoding: ${FILE_PUP_DOUBLE} ---"
run_encoding_on_instances "pup_double" "${FILE_PUP_DOUBLE}" "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run "yes"

# ============================================================================
# CSV: istanze DoubleVariant (pup, pup_heur, pup_doublev)
# ============================================================================

CSV_DOUBLEV="${TIMINGS_DIR}/pup_doublev_results.csv"
echo "n,variant,seed,solving_s,total_s,choices,conflicts,restarts,rules,variables,memory_mb" > "${CSV_DOUBLEV}"

echo ""
echo "================================================================"
echo "  BENCHMARK PUP — Istanze DoubleVariant"
echo "  Directory: ${INSTANCES_DOUBLEV}"
echo "================================================================"

echo ""
echo "--- Encoding: ${FILE_PUP} ---"
run_encoding_on_instances "pup"         "${FILE_PUP}"         "${INSTANCES_DOUBLEV}" "${CSV_DOUBLEV}" "${total_runs}" current_run "no"

echo ""
echo "--- Encoding: ${FILE_PUP_HEUR} ---"
run_encoding_on_instances "pup_heur"    "${FILE_PUP_HEUR}"    "${INSTANCES_DOUBLEV}" "${CSV_DOUBLEV}" "${total_runs}" current_run "yes"

echo ""
echo "--- Encoding: ${FILE_PUP_DOUBLEV} ---"
run_encoding_on_instances "pup_doublev" "${FILE_PUP_DOUBLEV}" "${INSTANCES_DOUBLEV}" "${CSV_DOUBLEV}" "${total_runs}" current_run "yes"

# ============================================================================
# FINE
# ============================================================================

echo ""
echo "================================================================"
echo "  Benchmark PUP completato. ${current_run} esecuzioni totali."
echo "  Risultati Double:       ${CSV_DOUBLE}"
echo "  Risultati DoubleVariant: ${CSV_DOUBLEV}"
echo "================================================================"
