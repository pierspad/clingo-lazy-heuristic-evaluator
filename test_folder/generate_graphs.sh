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
#
# Copia automatica nella tesi:
#   COPY_THESIS_GRAPHS=0 ./generate_graphs.sh
#       disattiva la copia in thesis/Tesi_Lazy_Heuristics.
#
#   THESIS_GRAPHS_DIR=/path/tesi/figures/bsp ./generate_graphs.sh
#       cambia la cartella di destinazione.
#
#   THESIS_SD_MAX_WIDTH=900 ./generate_graphs.sh
#       cambia la larghezza massima delle copie SD.
#
# La struttura prodotta e':
#   thesis/Tesi_Lazy_Heuristics/figures/bsp/HD/<set>/*.png
#   thesis/Tesi_Lazy_Heuristics/figures/bsp/SD/<set>/*.png
# ==============================================================================
PYTHON_BIN="${PYTHON_BIN:-python3}"
RESET_GRAPHS="${RESET_GRAPHS:-1}"
COPY_THESIS_GRAPHS="${COPY_THESIS_GRAPHS:-1}"
THESIS_GRAPHS_RESET="${THESIS_GRAPHS_RESET:-1}"
THESIS_SD_MAX_WIDTH="${THESIS_SD_MAX_WIDTH:-900}"
DEFAULT_BSP_GRAPH_SETS=(
    "standard:"
    "no_la_co:la_co"
    "no_la_co_no_ga_dyn:la_co,ga_dyn"
    "no_la_co_no_ga_dyn_no_la_aux:la_co,ga_dyn,la_aux"
)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "${SCRIPT_DIR}"
THESIS_GRAPHS_DIR="${THESIS_GRAPHS_DIR:-${SCRIPT_DIR}/../thesis/Tesi_Lazy_Heuristics/figures/bsp}"

copy_graphs_to_thesis() {
    if [[ "${COPY_THESIS_GRAPHS}" != "1" ]]; then
        echo "Copia grafici nella tesi disattivata (COPY_THESIS_GRAPHS=${COPY_THESIS_GRAPHS})."
        return 0
    fi

    local source_dir="${SCRIPT_DIR}/results/graphs/bsp"
    if [[ ! -d "${source_dir}" ]]; then
        echo "Nessuna directory BSP trovata in '${source_dir}', salto la copia nella tesi."
        return 0
    fi

    "${PYTHON_BIN}" - "${source_dir}" "${THESIS_GRAPHS_DIR}" "${THESIS_SD_MAX_WIDTH}" "${THESIS_GRAPHS_RESET}" <<'PY'
import shutil
import sys
from pathlib import Path

source_dir = Path(sys.argv[1]).resolve()
target_root = Path(sys.argv[2]).resolve()
sd_max_width = int(sys.argv[3])
reset_targets = sys.argv[4] == "1"

hd_dir = target_root / "HD"
sd_dir = target_root / "SD"

if reset_targets:
    for directory in (hd_dir, sd_dir):
        if directory.exists():
            shutil.rmtree(directory)

hd_dir.mkdir(parents=True, exist_ok=True)
sd_dir.mkdir(parents=True, exist_ok=True)

try:
    from PIL import Image
except ImportError:
    Image = None

copied = 0
sd_resized = 0

for source_file in sorted(source_dir.rglob("*.png")):
    relative_path = source_file.relative_to(source_dir)
    hd_file = hd_dir / relative_path
    sd_file = sd_dir / relative_path

    hd_file.parent.mkdir(parents=True, exist_ok=True)
    sd_file.parent.mkdir(parents=True, exist_ok=True)

    shutil.copy2(source_file, hd_file)

    if Image is None or sd_max_width <= 0:
        shutil.copy2(source_file, sd_file)
    else:
        with Image.open(source_file) as image:
            width, height = image.size
            if width > sd_max_width:
                sd_height = max(1, round(height * sd_max_width / width))
                resample = getattr(Image, "Resampling", Image).LANCZOS
                output = image.resize((sd_max_width, sd_height), resample)
                sd_resized += 1
            else:
                output = image.copy()

            save_options = {"optimize": True}
            if "dpi" in image.info:
                save_options["dpi"] = image.info["dpi"]
            output.save(sd_file, **save_options)

    copied += 1

print(
    f"Copiati {copied} grafici in '{target_root}' "
    f"(HD originali, SD max {sd_max_width}px; ridotti {sd_resized})."
)
if Image is None:
    print("Pillow non disponibile: le copie SD sono identiche agli originali HD.")
PY
}

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

copy_graphs_to_thesis
