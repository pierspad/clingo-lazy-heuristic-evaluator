#!/usr/bin/env bash
# ============================================================
# sync_hpc_figures.sh — copia i grafici della campagna HPC dentro
# thesis/Tesi_Lazy_Heuristics/figures/hpc/{HD,SD}/{bsp,pup,hrp}/.
#
# HD = PNG originale prodotto da tools/plot_results.py (200 dpi).
# SD = ridimensionato a larghezza 900px (stesso rapporto HD->SD gia'
#      usato per le figure della campagna locale in figures/bsp/).
#
# La tesi seleziona HD o SD con la macro \ThesisGraphQuality nel
# preambolo di Spadafora_Pierpaolo_Thesis.tex.
#
# Sorgente: clingo_hpc_graphs/ (scaricata dall'HPC con copyhpcgraphs).
# Uso:  sh thesis/sync_hpc_figures.sh          (dalla root del repo)
#       sh sync_hpc_figures.sh                 (da thesis/)
# Rilanciarlo e' idempotente: sovrascrive i PNG con la versione corrente.
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(dirname "$HERE")"
SRC="$REPO_ROOT/clingo_hpc_graphs"
DST="$HERE/Tesi_Lazy_Heuristics/figures/hpc"

# ImageMagick: IM7 usa `magick`, IM6 `convert`. Stesso identico resize.
if command -v magick >/dev/null 2>&1; then IM=magick; else IM=convert; fi
SD_WIDTH=900

[ -d "$SRC" ] || { echo "ERRORE: $SRC non trovata (hai eseguito copyhpcgraphs?)"; exit 1; }

# ---- selezione dei grafici usati in tesi --------------------------------
# formato: <cartella sorgente>|<file sorgente>|<famiglia>|<nome destinazione>
FIGURES=(
  # BSP
  "graphs-native/1_BSP|clingo_total.png|bsp|native_clingo_total.png"
  "graphs-native/1_BSP|solving.png|bsp|native_solving.png"
  "graphs-native/1_BSP|mem.png|bsp|native_mem.png"
  "graphs-native/1_BSP|choices.png|bsp|native_choices.png"
  "graphs-native/1_BSP|conflicts.png|bsp|native_conflicts.png"
  "graphs-comparison-native-prolog/1_BSP|solving.png|bsp|comparison_solving.png"
  "graphs-prolog/1_BSP|decide_calls.png|bsp|prolog_decide_calls.png"
  "graphs-prolog/1_BSP|prolog_ms_per_decide.png|bsp|prolog_ms_per_decide.png"
  "graphs-prolog/1_BSP|avg_candidates_per_decide.png|bsp|prolog_avg_candidates.png"
  # PUP
  "graphs-native/2_PUP|clingo_total.png|pup|native_clingo_total.png"
  "graphs-native/2_PUP|grounding.png|pup|native_grounding.png"
  "graphs-native/2_PUP|mem.png|pup|native_mem.png"
  "graphs-native/2_PUP|solving.png|pup|native_solving.png"
  "graphs-comparison-native-prolog/2_PUP|solving.png|pup|comparison_solving.png"
  "graphs-prolog/2_PUP|total_state_sync_time_ms.png|pup|prolog_state_sync.png"
  # HRP
  "graphs-native/3_HRP|solving.png|hrp|native_solving.png"
  "graphs-native/3_HRP|choices.png|hrp|native_choices.png"
  "graphs-comparison-native-prolog/3_HRP|solving.png|hrp|comparison_solving.png"
  "graphs-prolog/3_HRP|prolog_ms_per_decide.png|hrp|prolog_ms_per_decide.png"
  "graphs-prolog/3_HRP|avg_candidates_per_decide.png|hrp|prolog_avg_candidates.png"
)

copied=0 missing=0
for spec in "${FIGURES[@]}"; do
  IFS='|' read -r srcdir srcfile fam dstfile <<<"$spec"
  src="$SRC/$srcdir/$srcfile"
  if [ ! -f "$src" ]; then
    echo "!! manca: $src"
    missing=$((missing+1))
    continue
  fi
  mkdir -p "$DST/HD/$fam" "$DST/SD/$fam"
  cp -f "$src" "$DST/HD/$fam/$dstfile"
  "$IM" "$src" -resize "${SD_WIDTH}x" "$DST/SD/$fam/$dstfile"
  copied=$((copied+1))
done

echo "OK: $copied figure copiate in $DST (HD originali + SD ${SD_WIDTH}px via $IM)."
[ "$missing" -eq 0 ] || echo "ATTENZIONE: $missing figure mancanti (vedi sopra)."
