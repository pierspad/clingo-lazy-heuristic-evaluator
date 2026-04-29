#!/usr/bin/env bash
# benchmark_bsp.sh
# Benchmark per il problema BSP (Balanced Sum Partition).
# Testa 5 configurazioni con il binario clingo modificato:
#   std      — encoding dichiarativo puro  (BSP/BSP.lp)
#   std_aux  — #heuristic riscritta con predicato ausiliario (BSP/BSP_aux.lp)
#   lg       — lazy grounding              (BSP/BSP_lg.lp)
#   lg_aux   — lazy grounding con predicato ausiliario (BSP/BSP_aux_lg.lp)
#   colg     — lazy grounding + vincolo ottimizzato (BSP/BSP_colg.lp)
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
FILE_STD="BSP/BSP.lp"
FILE_STD_AUX="BSP/BSP_aux.lp"
FILE_LG="BSP/BSP_lg.lp"
FILE_LG_AUX="BSP/BSP_aux_lg.lp"
FILE_COLG="BSP/BSP_colg.lp"

# Varianti da eseguire.
# Per riattivare colg, aggiungi "colg" alla lista sotto.
# Puoi anche sovrascrivere da shell, ad esempio:
#   BSP_VARIANTS="std std_aux lg lg_aux colg" ./benchmark_bsp.sh
DEFAULT_VARIANTS=(std std_aux lg lg_aux)
read -r -a ACTIVE_VARIANTS <<< "${BSP_VARIANTS:-${DEFAULT_VARIANTS[*]}}"

# Range file (in BSP_instances/)
FILE_RANGE="BSP_instances/BSP_range.lp"

N_START=10
N_END=100
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
        lg) echo "${FILE_LG}" ;;
        lg_aux) echo "${FILE_LG_AUX}" ;;
        colg) echo "${FILE_COLG}" ;;
        *)
            echo "Errore: variante BSP sconosciuta '$1'." >&2
            echo "Varianti valide: std std_aux lg lg_aux colg" >&2
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
        std|std_aux)
            run_stats "${n}" "${variant}" "${seed}" \
                "${CLINGO_MOD}" "${FILE_RANGE}" "${file}" "-c" "n=${n}" "-n" "1" \
                "--heuristic=Domain" "--time-limit=${TIMEOUT_SECONDS}"
            ;;
        lg|lg_aux|colg)
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

echo "n,variant,seed,solving_s,total_s,choices,conflicts,restarts,rules,variables,memory_mb,ground_heuristics,ground_lazy_heuristic_facts,ground_facts" > "${CSV_FILE}"

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

    local counts ground_text
    if ground_text="$(timeout "${TIMEOUT_SECONDS}" "${cmd[@]}" --text 2>/dev/null)"; then
        local heur lazy facts
        heur="$(printf "%s\n" "${ground_text}" | { grep '^#heuristic' || true; } | wc -l | tr -d '[:space:]')"
        lazy="$(printf "%s\n" "${ground_text}" | { grep '^__heuristic(' || true; } | wc -l | tr -d '[:space:]')"
        facts="$(printf "%s\n" "${ground_text}" \
            | { grep '\.$' || true; } \
            | { grep -v ':-' || true; } \
            | { grep -v '^[[:space:]]*%' || true; } \
            | { grep -v '^#heuristic' || true; } \
            | wc -l | tr -d '[:space:]')"
        counts="${heur},${lazy},${facts}"
    else
        counts="NA,NA,NA"
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

run_stats() {
    local n="$1"
    local variant="$2"
    local seed="$3"
    shift 3
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

    local ground_counts ground_heuristics ground_lazy_heuristic_facts ground_facts
    ground_counts="$(collect_ground_counts "${cmd[@]}")"
    IFS=',' read -r ground_heuristics ground_lazy_heuristic_facts ground_facts <<< "${ground_counts}"

    echo "    solving=${solving_s}s total=${total_s}s choices=${choices} conflicts=${conflicts} restarts=${restarts} rules=${rules} vars=${variables} mem=${memory_mb}MB heur=${ground_heuristics} lazy_facts=${ground_lazy_heuristic_facts} facts=${ground_facts}"
    echo "${n},${variant},${seed},${solving_s},${total_s},${choices},${conflicts},${restarts},${rules},${variables},${memory_mb},${ground_heuristics},${ground_lazy_heuristic_facts},${ground_facts}" >> "${CSV_FILE}"
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
