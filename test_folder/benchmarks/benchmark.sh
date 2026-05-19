#!/usr/bin/env bash
# benchmark.sh
# Launcher unico: esegue benchmark BSP e benchmark PUP in sequenza.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
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

echo "==============================================================="
echo " Avvio benchmark BSP"
echo "==============================================================="
bash "${BSP_SCRIPT}"

echo ""
echo "==============================================================="
echo " Avvio benchmark PUP"
echo "==============================================================="
bash "${PUP_SCRIPT}"

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
