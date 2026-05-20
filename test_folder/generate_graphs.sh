#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# CONFIGURAZIONE GRAFICI
#
# Ogni voce di DEFAULT_BSP_GRAPH_SETS ha la forma:
#
#   nome_set:variante_da_escludere,variante_da_escludere,...
#
# - La parte prima di ":" serve solo come etichetta leggibile nei log.
# - La parte dopo ":" e' la lista delle varianti BSP da togliere dai grafici.
# - Lascia la parte dopo ":" vuota per generare il set completo standard.
# - Per aggiungere un nuovo set, aggiungi una nuova riga all'array.
# - Per non generare piu' un set, commenta o rimuovi la riga.
#
# Varianti BSP valide:
#   gc_noheur gc ga ga_dyn la lc la_aux la_co
#
# Esempi:
#   "standard:"                         -> tutte le varianti
#   "no_la_co:la_co"                    -> esclude solo la_co
#   "core_only:la_co,ga_dyn,la_aux"     -> esclude tre varianti
#
# Override rapido da shell:
#   BSP_GRAPH_SETS="standard: core_only:la_co,ga_dyn,la_aux" ./generate_graphs.sh
#
# Compatibilita' legacy:
#   BSP_GRAPH_EXCLUDES="__standard__ bsplaco" ./generate_graphs.sh
# ==============================================================================
PYTHON_BIN="${PYTHON_BIN:-python3}"
RESET_GRAPHS="${RESET_GRAPHS:-1}"
DEFAULT_BSP_GRAPH_SETS=(
    "standard:"
    "no_la_co:la_co"
    "no_la_co_no_ga_dyn:la_co,ga_dyn"
    "no_la_co_no_ga_dyn_no_la_aux:la_co,ga_dyn,la_aux"
)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "${SCRIPT_DIR}"

if [[ -n "${BSP_GRAPH_SETS:-}" ]]; then
    read -r -a ACTIVE_BSP_GRAPH_SETS <<< "${BSP_GRAPH_SETS}"
elif [[ -n "${BSP_GRAPH_EXCLUDES:-}" ]]; then
    ACTIVE_BSP_GRAPH_SETS=()
    for exclude in ${BSP_GRAPH_EXCLUDES}; do
        if [[ "${exclude}" == "__standard__" ]]; then
            ACTIVE_BSP_GRAPH_SETS+=("standard:")
        else
            ACTIVE_BSP_GRAPH_SETS+=("legacy_${exclude}:${exclude}")
        fi
    done
else
    ACTIVE_BSP_GRAPH_SETS=("${DEFAULT_BSP_GRAPH_SETS[@]}")
fi

if [ "${RESET_GRAPHS}" = "1" ]; then
    "${PYTHON_BIN}" tools/gen_graphs.py --reset
fi

for graph_set in "${ACTIVE_BSP_GRAPH_SETS[@]}"; do
    if [[ "${graph_set}" == *":"* ]]; then
        set_name="${graph_set%%:*}"
        excluded_variants="${graph_set#*:}"
    else
        set_name="custom"
        excluded_variants="${graph_set}"
    fi

    if [[ -z "${excluded_variants}" || "${excluded_variants}" == "__standard__" ]]; then
        echo "Genero grafici BSP '${set_name}' senza esclusioni."
        "${PYTHON_BIN}" tools/gen_graphs.py --type bsp
    else
        echo "Genero grafici BSP '${set_name}' escludendo: ${excluded_variants}"
        "${PYTHON_BIN}" tools/gen_graphs.py --type bsp --exclude "${excluded_variants}"
    fi
done
