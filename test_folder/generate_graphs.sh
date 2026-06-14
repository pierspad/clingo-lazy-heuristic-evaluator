#!/usr/bin/env bash
# ============================================================
# Genera tutti i grafici dai CSV per-backend e (opzionale) copia i grafici
# BSP nativi nella tesi in versione HD + SD.
#
# Struttura prodotta da tools/gen_graphs.py:
#   graphs-native/{1_BSP,2_PUP}/         tutte le varianti, backend native
#   graphs-prolog/{1_BSP,2_PUP}/         tutte le varianti, backend prolog
#   graphs-native-prolog/{1_BSP,2_PUP}/  confronto native-vs-prolog (lazy)
#
# Override da shell:
#   RESET_GRAPHS=0            non svuotare gli alberi grafici prima di generare.
#   PYTHON_BIN=/path/python   interprete con matplotlib/numpy installati.
#   COPY_THESIS_GRAPHS=0      disattiva la copia nella tesi.
#   THESIS_GRAPHS_DIR=...     cartella di destinazione (default figures/bsp).
#   THESIS_GRAPHS_SRC=...     sorgente da copiare (default graphs-native/1_BSP).
#   THESIS_SD_MAX_WIDTH=900   larghezza massima delle copie SD.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "${SCRIPT_DIR}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
RESET_GRAPHS="${RESET_GRAPHS:-1}"
COPY_THESIS_GRAPHS="${COPY_THESIS_GRAPHS:-1}"
THESIS_GRAPHS_RESET="${THESIS_GRAPHS_RESET:-1}"
THESIS_SD_MAX_WIDTH="${THESIS_SD_MAX_WIDTH:-900}"
THESIS_GRAPHS_DIR="${THESIS_GRAPHS_DIR:-${SCRIPT_DIR}/thesis/Tesi_Lazy_Heuristics/figures/bsp}"
THESIS_GRAPHS_SRC="${THESIS_GRAPHS_SRC:-${SCRIPT_DIR}/graphs-native/1_BSP}"

if [ "${RESET_GRAPHS}" = "1" ]; then
    "${PYTHON_BIN}" tools/gen_graphs.py --reset
fi

# Genera tutto: BSP+PUP per ogni backend con CSV presenti, piu' il confronto.
"${PYTHON_BIN}" tools/gen_graphs.py

copy_graphs_to_thesis() {
    if [[ "${COPY_THESIS_GRAPHS}" != "1" ]]; then
        echo "Copia grafici nella tesi disattivata (COPY_THESIS_GRAPHS=${COPY_THESIS_GRAPHS})."
        return 0
    fi
    if [[ ! -d "${THESIS_GRAPHS_SRC}" ]]; then
        echo "Sorgente grafici '${THESIS_GRAPHS_SRC}' assente, salto la copia nella tesi."
        return 0
    fi

    "${PYTHON_BIN}" - "${THESIS_GRAPHS_SRC}" "${THESIS_GRAPHS_DIR}" "${THESIS_SD_MAX_WIDTH}" "${THESIS_GRAPHS_RESET}" <<'PY'
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

copy_graphs_to_thesis
