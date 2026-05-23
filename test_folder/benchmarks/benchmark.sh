#!/usr/bin/env bash
# benchmark.sh
# Launcher ufficiale per il benchmark BSP completo.
# Per profili specifici usare direttamente benchmark_bsp.sh.

set -euo pipefail

# Disable verbose lazy heuristic debug during benchmark runs unless explicitly allowed.
if [ "${ALLOW_LAZY_DEBUG:-0}" != "1" ]; then
  unset LAZY_HEURISTIC_DEBUG
  unset LAZY_PROLOG_STATS
fi

# ==============================================================================
# CONFIGURAZIONE BENCHMARK
#
# Override da shell:
#   TIMEOUT_SECONDS=120 N_END=100 ./test_folder/benchmarks/benchmark.sh
# ==============================================================================
export RUN_BSP="${RUN_BSP:-true}"
export RUN_PUP="${RUN_PUP:-false}"

export TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"
export REPEATS="${REPEATS:-1}"
export MEM_LIMIT_BYTES="${MEM_LIMIT_BYTES:-$((10 * 1024 * 1024 * 1024))}"
export N_START="${N_START:-10}"
export N_END="${N_END:-150}"
export N_STEP="${N_STEP:-10}"
export STOP_VARIANT_ON_LIMIT="${STOP_VARIANT_ON_LIMIT:-1}"

export BSP_VARIANTS="${BSP_VARIANTS:-gc_noheur gc ga la la_co lc}"

export BSP_RESULTS_CSV="${BSP_RESULTS_CSV:-test_folder/results/profiles/bsp_full_results.csv}"
export BSP_METADATA_FILE="${BSP_METADATA_FILE:-test_folder/results/profiles/bsp_full_metadata.json}"
export BSP_FAILURES_FILE="${BSP_FAILURES_FILE:-test_folder/results/profiles/bsp_full_failures.txt}"
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BSP_SCRIPT="${SCRIPT_DIR}/benchmark_bsp.sh"
PUP_SCRIPT="${SCRIPT_DIR}/benchmark_pup.sh"

if [ ! -f "${BSP_SCRIPT}" ]; then
  echo "Errore: script BSP non trovato: ${BSP_SCRIPT}" >&2
  exit 1
fi

START_TIME=$(date +%s)

if [ "${RUN_BSP}" = "true" ]; then
  echo "==============================================================="
  echo " Avvio benchmark BSP"
  echo "==============================================================="
  bash "${BSP_SCRIPT}"
else
  echo "==============================================================="
  echo " Benchmark BSP disabilitato (RUN_BSP!=true)"
  echo "==============================================================="
fi

echo ""
if [ "${RUN_PUP}" = "true" ]; then
  if [ ! -f "${PUP_SCRIPT}" ]; then
    echo "Errore: script PUP non trovato: ${PUP_SCRIPT}" >&2
    exit 1
  fi
  echo "==============================================================="
  echo " Avvio benchmark PUP"
  echo "==============================================================="
  bash "${PUP_SCRIPT}"
else
  echo "==============================================================="
  echo " Benchmark PUP disabilitato (RUN_PUP!=true)"
  echo "==============================================================="
fi

echo ""
END_TIME=$(date +%s)
TOTAL_SECONDS=$((END_TIME - START_TIME))
HOURS=$((TOTAL_SECONDS / 3600))
MINUTES=$(((TOTAL_SECONDS % 3600) / 60))
SECONDS_REMAINING=$((TOTAL_SECONDS % 60))

echo "==============================================================="
echo " Benchmark completato."
printf " Durata totale: %02d ore, %02d minuti, %02d secondi\n" "$HOURS" "$MINUTES" "$SECONDS_REMAINING"
echo " Risultati disponibili in ${TEST_ROOT}/results"
echo " CSV: ${BSP_RESULTS_CSV}"
echo " Metadata: ${BSP_METADATA_FILE}"
echo " Failures: ${BSP_FAILURES_FILE}"
echo "==============================================================="