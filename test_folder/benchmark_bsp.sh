#!/usr/bin/env bash
# benchmark_bsp.sh
# Benchmark per il problema BSP (Balanced Sum Partition).
# Testa le configurazioni con il binario clingo modificato:
#   std      — ground & solve con semantica Clingo (BSP/BSP_gscs.lp)
#   std_aux  — ground & solve con semantica Clingo + ausiliari (BSP/BSP_gscs_aux.lp)
#   gsas     — alpha semantics ground-and-solve (BSP/BSP_gsas.lp)
#   lg       — lazy grounding con semantica Alpha (BSP/BSP_lgas.lp)
#   lgcs     — lazy grounding con semantica Clingo (BSP/BSP_lgcs.lp)
#   auxlg    — lazy grounding con semantica Alpha + ausiliari (BSP/BSP_lgas_aux.lp)
#   lgas_co  — lazy grounding + vincolo ottimizzato (BSP/BSP_lgas_co.lp)
#
# Ogni combinazione (N, variant) viene eseguita REPEATS volte con seed diversi.
# Le varianti con euristiche usano --heuristic=Domain.
# Ogni run è protetta da timeout esterno a 600s e limite memoria 32GiB (se prlimit è disponibile).
# Salva i risultati in ./test-results/bsp_results.csv

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

if [ -z "${CLINGO_MOD}" ]; then
    echo "Errore: binario clingo modificato non trovato. Percorsi provati:"
    echo "  - ${REPO_ROOT}/build/bin/clingo"
    echo "  - ${REPO_ROOT}/clingo-modified/build/bin/clingo"
    exit 1
fi

cd "${SCRIPT_DIR}"

# Encoding files
FILE_STD="BSP/BSP_gscs.lp"
FILE_STD_AUX="BSP/BSP_gscs_aux.lp"
FILE_ASGS="BSP/BSP_gsas.lp"
FILE_LG="BSP/BSP_lgas.lp"
FILE_CSLG="BSP/BSP_lgcs.lp"
FILE_AUXLG="BSP/BSP_lgas_aux.lp"
FILE_COLG="BSP/BSP_lgas_co.lp"

# Varianti da eseguire.
# Per riattivare lgas_co, aggiungi "lgas_co" alla lista sotto.
# Puoi anche sovrascrivere da shell, ad esempio:
#   BSP_VARIANTS="std std_aux gsas lg lgcs auxlg lgas_co" ./benchmark_bsp.sh
DEFAULT_VARIANTS=(std std_aux gsas lg lgcs auxlg)
read -r -a ACTIVE_VARIANTS <<< "${BSP_VARIANTS:-${DEFAULT_VARIANTS[*]}}"

# Range file (in BSP_instances/)
FILE_RANGE="BSP_instances/BSP_range.lp"

N_START=10
N_END=70
N_STEP=10

# Numero di ripetizioni per ogni (N, variant) con seed diversi
REPEATS=3

TIMINGS_DIR="./test-results"
CSV_FILE="${TIMINGS_DIR}/bsp_results.csv"

mkdir -p "${TIMINGS_DIR}"
declare -A GROUND_COUNT_CACHE

variant_file() {
    case "$1" in
        std) echo "${FILE_STD}" ;;
        std_aux) echo "${FILE_STD_AUX}" ;;
        asgs|gsas) echo "${FILE_ASGS}" ;;
        lg) echo "${FILE_LG}" ;;
        cslg|lgcs) echo "${FILE_CSLG}" ;;
        auxlg|lg_aux) echo "${FILE_AUXLG}" ;;
        colg|lgas_co) echo "${FILE_COLG}" ;;
        *)
            echo "Errore: variante BSP sconosciuta '$1'." >&2
            echo "Varianti valide: std std_aux gsas/asgs lg lgcs/cslg auxlg lgas_co/colg" >&2
            exit 1
            ;;
    esac
}

run_variant_for_seed() {
    local n="$1"
    local variant="$2"
    local seed="$3"
    local file
    file="$(variant_file "${variant}")"

    case "${variant}" in
        std|std_aux|asgs|gsas)
            run_stats "${n}" "${variant}" "${seed}" \
                "${CLINGO_MOD}" "${FILE_RANGE}" "${file}" "-c" "n=${n}" "-n" "1" \
                "--heuristic=Domain" "--time-limit=${TIMEOUT_SECONDS}"
            ;;
        lg|cslg|lgcs|auxlg|lg_aux|colg|lgas_co)
            run_stats "${n}" "${variant}" "${seed}" \
                "${CLINGO_MOD}" "${FILE_RANGE}" "${file}" "-n" "1" "-c" "n=${n}" \
                "--heuristic=Domain" "--time-limit=${TIMEOUT_SECONDS}"
            ;;
    esac
}

ENABLED_VARIANTS=()
for variant in "${ACTIVE_VARIANTS[@]}"; do
    file="$(variant_file "${variant}")"
    if [ -f "${file}" ]; then
        ENABLED_VARIANTS+=("${variant}")
    else
        echo "Avviso: salto variante '${variant}' perché il file '${file}' non esiste."
    fi
done

if [ "${#ENABLED_VARIANTS[@]}" -eq 0 ]; then
    echo "Errore: nessuna variante BSP attiva con file esistente."
    exit 1
fi

echo "Varianti BSP attive: ${ENABLED_VARIANTS[*]}"

# ============================================================================
# INTESTAZIONE CSV
# ============================================================================

echo "n,variant,seed,solving_s,total_s,grounding_s,choices,conflicts,restarts,rules,variables,memory_mb,ground_heuristics,ground_lazy_heuristic_facts,ground_facts,ground_lines" > "${CSV_FILE}"

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

collect_ground_counts() {
    local cmd=("$@")
    local cache_key="${cmd[*]}"

    if [[ -n "${GROUND_COUNT_CACHE[${cache_key}]:-}" ]]; then
        printf "%s" "${GROUND_COUNT_CACHE[${cache_key}]}"
        return
    fi

    local counts
    if counts="$(timeout "${TIMEOUT_SECONDS}" "${cmd[@]}" --text 2>/dev/null | awk '
        BEGIN { heur=0; lazy=0; facts=0; lines=0; }
        { lines++; }
        /^#heuristic/ { heur++; next; }
        /^__heuristic\(/ { lazy++; facts++; next; }
        /^[[:space:]]*%/ { next; }
        /\.$/ && $0 !~ /:-/ { facts++; }
        END { printf "%d,%d,%d,%d", heur, lazy, facts, lines; }
    ')"; then
        :
    else
        counts="NA,NA,NA,NA"
    fi

    # Versione precedente con awk, lasciata qui per ripristino rapido:
    # counts="$(timeout "${TIMEOUT_SECONDS}" "${cmd[@]}" --text 2>/dev/null | awk '
    #     BEGIN { heur=0; lazy=0; facts=0; }
    #     /^#heuristic/ { heur++; next; }
    #     /^__heuristic\(/ { lazy++; facts++; next; }
    #     /^[[:space:]]*%/ { next; }
    #     /\.$/ && $0 !~ /:-/ { facts++; }
    #     END { printf "%d,%d,%d", heur, lazy, facts; }
    # ' || printf "NA,NA,NA")"

    GROUND_COUNT_CACHE["${cache_key}"]="${counts}"
    printf "%s" "${counts}"
}

is_clingo_success_status() {
    case "$1" in
        0|10|20|30) return 0 ;;
        *) return 1 ;;
    esac
}

run_stats() {
    local n="$1"
    local variant="$2"
    local seed="$3"
    shift 3
    local cmd=("$@")

    echo "  [seed=${seed}] ${cmd[*]}"

    local output status
    if command -v prlimit >/dev/null 2>&1; then
        if output="$( { "${TIME_BIN}" -v prlimit --as="${MEM_LIMIT_BYTES}" -- timeout "${TIMEOUT_SECONDS}" "${cmd[@]}" --stats=2 --seed="${seed}" ; } 2>&1 )"; then
            status=0
        else
            status=$?
        fi
    else
        if output="$( { "${TIME_BIN}" -v timeout "${TIMEOUT_SECONDS}" "${cmd[@]}" --stats=2 --seed="${seed}" ; } 2>&1 )"; then
            status=0
        else
            status=$?
        fi
    fi

    local run_ok=1
    if ! is_clingo_success_status "${status}" || echo "${output}" | grep -qE '^\*\*\* ERROR|^UNKNOWN'; then
        run_ok=0
    fi

    local solving_s
    solving_s="$(echo "${output}" | grep -oP '(?<=Solving: )[0-9.]+(?=s)' | head -1 || echo "NA")"
    if [ -z "${solving_s}" ]; then solving_s="NA"; fi

    local total_s
    total_s="$(echo "${output}" | grep -P '^Time\s+:' | grep -oP '[0-9.]+(?=s)' | head -1 || echo "NA")"
    if [ -z "${total_s}" ]; then total_s="NA"; fi

    local grounding_s
    if [[ "${total_s}" =~ ^[0-9.]+$ && "${solving_s}" =~ ^[0-9.]+$ ]]; then
        grounding_s="$(awk -v total="${total_s}" -v solving="${solving_s}" 'BEGIN { v=total-solving; if (v < 0) v=0; printf "%.6f", v }')"
    else
        grounding_s="NA"
    fi

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

    if [ "${run_ok}" -eq 0 ]; then
        echo "    warning: clingo exited with status ${status}; solver metrics marked as NA"
        solving_s="NA"
        total_s="NA"
        grounding_s="NA"
        choices="NA"
        conflicts="NA"
        restarts="NA"
        rules="NA"
        variables="NA"
    fi

    local rss_kb memory_mb
    rss_kb="$(echo "${output}" | grep -oP '(?<=Maximum resident set size \(kbytes\): )\d+' || echo "")"
    if [ -z "${rss_kb}" ]; then
        memory_mb="NA"
    else
        memory_mb="$(echo "${rss_kb}" | awk '{printf "%.4f", $1/1024}')"
    fi
    if [ "${run_ok}" -eq 0 ]; then
        memory_mb="NA"
    fi

    local ground_counts ground_heuristics ground_lazy_heuristic_facts ground_facts ground_lines
    ground_counts="$(collect_ground_counts "${cmd[@]}")"
    IFS=',' read -r ground_heuristics ground_lazy_heuristic_facts ground_facts ground_lines <<< "${ground_counts}"

    local memory_display="${memory_mb}MB"
    if [ "${memory_mb}" = "NA" ]; then
        memory_display="NA"
    fi

    echo "    grounding=${grounding_s}s solving=${solving_s}s total=${total_s}s choices=${choices} conflicts=${conflicts} restarts=${restarts} rules=${rules} vars=${variables} mem=${memory_display} heur=${ground_heuristics} lazy_facts=${ground_lazy_heuristic_facts} facts=${ground_facts} ground_lines=${ground_lines}"
    echo "${n},${variant},${seed},${solving_s},${total_s},${grounding_s},${choices},${conflicts},${restarts},${rules},${variables},${memory_mb},${ground_heuristics},${ground_lazy_heuristic_facts},${ground_facts},${ground_lines}" >> "${CSV_FILE}"
}

# ============================================================================
# LOOP PRINCIPALE
# ============================================================================

total_runs=$(( ((N_END - N_START) / N_STEP + 1) * ${#ENABLED_VARIANTS[@]} * REPEATS ))
current_run=0

for n in $(seq "${N_START}" "${N_STEP}" "${N_END}"); do
    echo ""
    echo "=== N=${n} ==="

    for variant in "${ENABLED_VARIANTS[@]}"; do
        for seed in $(seq 1 "${REPEATS}"); do
            current_run=$((current_run + 1))
            echo "--- ${variant} (run ${current_run}/${total_runs}) ---"
            run_variant_for_seed "${n}" "${variant}" "${seed}"
        done
    done
done

echo ""
echo "Benchmark BSP completato. ${current_run} esecuzioni totali."
echo "Risultati salvati in: ${CSV_FILE}"
