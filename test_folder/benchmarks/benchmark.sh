#!/usr/bin/env bash
# Launcher ufficiale della suite benchmark.
# La configurazione dei singoli benchmark vive negli script dedicati.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BSP_SCRIPT="${SCRIPT_DIR}/benchmark_bsp.sh"
PUP_SCRIPT="${SCRIPT_DIR}/benchmark_pup.sh"

# Disable verbose lazy heuristic debug during benchmark runs unless explicitly allowed.
if [ "${ALLOW_LAZY_DEBUG:-0}" != "1" ]; then
  unset LAZY_HEURISTIC_DEBUG
  unset LAZY_PROLOG_STATS
fi

# ==============================================================================
# CONFIGURAZIONE LAUNCHER
#
# Questo file decide solo quali benchmark lanciare. I parametri BSP/PUP stanno
# nei rispettivi script:
#   test_folder/benchmarks/benchmark_bsp.sh
#   test_folder/benchmarks/benchmark_pup.sh
#
# Override da shell:
#   RUN_BSP=true RUN_PUP=false ./test_folder/benchmarks/benchmark.sh
# ==============================================================================
export RUN_BSP="${RUN_BSP:-true}"
export RUN_PUP="${RUN_PUP:-false}"
# ==============================================================================

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
echo "==============================================================="
