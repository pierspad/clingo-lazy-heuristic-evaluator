#!/usr/bin/env sh

# ==============================================================================
# CONFIGURAZIONE GRAFICI
# Usa "__standard__" per generare il set BSP senza esclusioni.
# Esempio:
#   BSP_GRAPH_EXCLUDES="__standard__ bsplaco" ./generate_graphs.sh
# ==============================================================================
PYTHON_BIN="${PYTHON_BIN:-python3}"
RESET_GRAPHS="${RESET_GRAPHS:-1}"
BSP_GRAPH_EXCLUDES="${BSP_GRAPH_EXCLUDES:-__standard__ bsplaco bsplaco,bspgadyn bsplaco,bspgadyn,bsplaaux}"
# ==============================================================================

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "${SCRIPT_DIR}"

if [ "${RESET_GRAPHS}" = "1" ]; then
    "${PYTHON_BIN}" tools/gen_graphs.py --reset
fi

for exclude in ${BSP_GRAPH_EXCLUDES}; do
    case "${exclude}" in
        __standard__)
            "${PYTHON_BIN}" tools/gen_graphs.py --type bsp
            ;;
        *)
            "${PYTHON_BIN}" tools/gen_graphs.py --type bsp --exclude "${exclude}"
            ;;
    esac
done
