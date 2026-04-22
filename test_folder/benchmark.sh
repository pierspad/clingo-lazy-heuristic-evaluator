#!/usr/bin/env bash
# benchmark.sh
# Launcher unico: esegue benchmark BSP e benchmark PUP in sequenza.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
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
echo "==============================================================="
echo " Benchmark completi (BSP + PUP)."
echo " Risultati disponibili in ./test-results"
echo "==============================================================="
