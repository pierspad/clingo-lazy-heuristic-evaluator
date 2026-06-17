#!/usr/bin/env bash
# ============================================================
# Orchestratore: esegue tutti i benchmark per i backend richiesti.
#
# Per ogni backend selezionato lancia BSP, PUP e/o HRP riusando i wrapper:
#   1_native_bsp.sh / 1_prolog_bsp.sh   (BSP)
#   2_native_pup.sh / 2_prolog_pup.sh   (PUP)
#   3_native_hrp.sh / 3_prolog_hrp.sh   (HRP)
#
# I risultati finiscono in results-<backend>/ (vedi _bench_lib.sh):
#   results-native/1_BSP_native.csv   results-native/2_PUP_native.csv   results-native/3_HRP_native.csv
#   results-prolog/1_BSP_prolog.csv   results-prolog/2_PUP_prolog.csv   results-prolog/3_HRP_prolog.csv
#
# Override via ambiente:
#   BACKENDS   backend da eseguire, spazio-separati (default "native prolog")
#   RUN_BSP    "true"/"false"  (default true)
#   RUN_PUP    "true"/"false"  (default true)
#   RUN_HRP    "true"/"false"  (default true)
#   piu' tutti gli override di _bench_lib.sh (TIMEOUT, VARIANTS, SEEDS,
#   N_START/N_END/N_STEP, PUP_GLOB, HRP_GLOB, ...).
#
# Esempio "run veloce" di prova:
#   N_START=10 N_END=12 PUP_GLOB='.../double-20.asp' ./0_benchmark.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BACKENDS="${BACKENDS:-native prolog}"
RUN_BSP="${RUN_BSP:-true}"
RUN_PUP="${RUN_PUP:-true}"
RUN_HRP="${RUN_HRP:-true}"

run_wrapper() {
    local script="$1" label="$2"
    if [ ! -f "${script}" ]; then
        echo "Errore: script non trovato: ${script}" >&2
        exit 1
    fi
    echo "==============================================================="
    echo " ${label}"
    echo "==============================================================="
    bash "${script}"
    echo ""
}

START_TIME=$(date +%s)

for backend in ${BACKENDS}; do
    case "${backend}" in
        native|prolog) ;;
        *) echo "Backend non valido: '${backend}' (usa native|prolog)" >&2; exit 1 ;;
    esac

    if [ "${RUN_BSP}" = "true" ]; then
        run_wrapper "${SCRIPT_DIR}/1_${backend}_bsp.sh" "BSP - backend ${backend}"
    else
        echo "BSP disabilitato (RUN_BSP=${RUN_BSP})."
    fi

    if [ "${RUN_PUP}" = "true" ]; then
        run_wrapper "${SCRIPT_DIR}/2_${backend}_pup.sh" "PUP - backend ${backend}"
    else
        echo "PUP disabilitato (RUN_PUP=${RUN_PUP})."
    fi

    if [ "${RUN_HRP}" = "true" ]; then
        run_wrapper "${SCRIPT_DIR}/3_${backend}_hrp.sh" "HRP - backend ${backend}"
    else
        echo "HRP disabilitato (RUN_HRP=${RUN_HRP})."
    fi
done

END_TIME=$(date +%s)
TOTAL_SECONDS=$((END_TIME - START_TIME))
printf "===============================================================\n"
printf " Benchmark completato.\n"
printf " Durata totale: %02d ore, %02d minuti, %02d secondi\n" \
    $((TOTAL_SECONDS / 3600)) $(((TOTAL_SECONDS % 3600) / 60)) $((TOTAL_SECONDS % 60))
printf " Backend eseguiti: %s\n" "${BACKENDS}"
printf " Risultati in: %s/results-<backend>/\n" "${TEST_ROOT}"
printf "===============================================================\n"
