#!/usr/bin/env bash
# benchmark.sh
# Launcher unico: esegue benchmark BSP e benchmark PUP in sequenza.

set -euo pipefail

# ==============================================================================
# CONFIGURAZIONE BENCHMARK
# Modifica questi parametri per cambiare il comportamento dei test.
# ==============================================================================
export RUN_BSP="true"
export RUN_PUP="false"

export TIMEOUT_SECONDS=180
export REPEATS=2
export MEM_LIMIT_BYTES=$((10 * 1024 * 1024 * 1024))
export N_START=10
export N_END=200
export N_STEP=10
export STOP_VARIANT_ON_LIMIT=1
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BSP_SCRIPT="${SCRIPT_DIR}/benchmark_bsp.sh"
PUP_SCRIPT="${SCRIPT_DIR}/benchmark_pup.sh"

if [ ! -f "${BSP_SCRIPT}" ]; then
  echo "Errore: script non trovato: ${BSP_SCRIPT}"
  exit 1
fi

if [ ! -f "${PUP_SCRIPT}" ]; then
  echo "Errore: script non trovato: ${PUP_SCRIPT}"
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
echo " Benchmark completi (BSP + PUP)."
printf " Durata totale: %02d ore, %02d minuti, %02d secondi\n" "$HOURS" "$MINUTES" "$SECONDS_REMAINING"
echo " Risultati disponibili in ${TEST_ROOT}/results"
echo "==============================================================="
