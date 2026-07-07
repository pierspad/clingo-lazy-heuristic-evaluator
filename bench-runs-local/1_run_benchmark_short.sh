#!/usr/bin/env bash
# ============================================================
#  TEST RAPIDO della suite di benchmark (sanity-check dei grafici).
#
#  Uso, dalla cartella root del repo:
#      sh 1_run_benchmark_short.sh
#
#  Cosa fa: prepara l'ambiente (venv/btool/runlim/clingo), costruisce un
#  MINI sottoinsieme isolato di istanze, lo esegue con un timeout breve e
#  produce i grafici in graphs-short/. NON tocca i dati della suite completa.
#  Serve solo a verificare velocemente che la pipeline e i grafici funzionino.
#
#  Idempotente: i run gia' completati vengono saltati. Per rifare tutto:
#      FORCE=1 sh 1_run_benchmark_short.sh
# ============================================================

# >>> se lanciato con `sh`, ri-eseguo sotto bash (servono feature bash) <<<
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

# ============================================================
#  COSTANTI MODIFICABILI
# ============================================================
TIMEOUT=15            # <-- timeout per istanza, in SECONDI (modifica qui)
SHORT_BSP_START=3     # range BSP ridotto per il test rapido
SHORT_BSP_END=6
SHORT_PUP_COUNT=2     # quante istanze PUP/HRP (le piu' piccole) includere
SHORT_HRP_COUNT=2
# ============================================================

# NB: questa copia vive in bench-runs-local/, un livello sotto la root del
# repo -> risalgo di uno per ritrovare test_folder/, clingo-native/, ecc.
# Per il resto e' identico all'originale in root (era gia' locale).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# La macchina btool vive in test_folder/benchmark_folder_clingo/ (cwd di btool).
TEST_DIR="$REPO_ROOT/test_folder/benchmark_folder_clingo"
# shellcheck disable=SC1091
. "$TEST_DIR/scripts/bench_common.sh"

# percorsi isolati per la short (relativi a benchmark_folder_clingo)
SHORT_BENCH="benchmarks/_short"
SHORT_OUTPUT="output-short"
SHORT_RS="runscripts/runscript.short.xml"
SHORT_RESULTS="results-short.xml"
# La short e' un sanity-check: i suoi grafici restano DENTRO la cartella btool
# (out-base ".") per non sporcare test_folder/ con i grafici di prova.
SHORT_GRAPHS="."

# copia le N istanze piu' piccole (per taglia numerica) da src a dst
copy_smallest() {
  local src="$1" dst="$2" count="$3"
  mkdir -p "$dst"
  [ -d "$src" ] || { warn "sorgente istanze assente: $src"; return 0; }
  ls "$src" 2>/dev/null | sort -t- -k2 -n | head -n "$count" | while read -r f; do
    cp -f "$src/$f" "$dst/$f"
  done
}

build_short_subset() {
  log "Costruisco il mini-subset isolato in $SHORT_BENCH/ ..."
  rm -rf "$SHORT_BENCH"; mkdir -p "$SHORT_BENCH"

  # BSP: rigenero un range piccolo (#const n=N)
  python3 tools/gen_bsp_instances.py \
    --out "$SHORT_BENCH/BSP" --start "$SHORT_BSP_START" --end "$SHORT_BSP_END" --step 1 --clean \
    || die "generazione istanze BSP short fallita"

  # PUP / HRP: prendo le piu' piccole dal set canonico (.bak), fallback al live
  local pup_src="benchmarks.bak/PUP"; [ -d "$pup_src" ] || pup_src="benchmarks/PUP"
  local hrp_src="benchmarks.bak/HRP"; [ -d "$hrp_src" ] || hrp_src="benchmarks/HRP"
  copy_smallest "$pup_src" "$SHORT_BENCH/PUP" "$SHORT_PUP_COUNT"
  copy_smallest "$hrp_src" "$SHORT_BENCH/HRP" "$SHORT_HRP_COUNT"

  ok "subset: BSP=$(ls "$SHORT_BENCH/BSP" 2>/dev/null | wc -l | tr -d ' ')  PUP=$(ls "$SHORT_BENCH/PUP" 2>/dev/null | wc -l | tr -d ' ')  HRP=$(ls "$SHORT_BENCH/HRP" 2>/dev/null | wc -l | tr -d ' ')"
}

# ============================================================
main() {
  log "TEST RAPIDO — timeout ${TIMEOUT}s, subset isolato (graphs-short/)"
  bootstrap_env
  ensure_runlim
  ensure_clingo_bins
  build_short_subset

  log "Derivo il runscript short ($SHORT_RS) ..."
  derive_runscript \
    "runscripts/runscript.xml" "$SHORT_RS" \
    "$TIMEOUT" "$SHORT_OUTPUT" \
    "$SHORT_BENCH/BSP" "$SHORT_BENCH/PUP" "$SHORT_BENCH/HRP" \
    "1"   # drop_hpc: la short gira solo in locale

  run_btool_pipeline "$SHORT_RS" "$SHORT_OUTPUT" "study-local" "local" \
    "$SHORT_RESULTS" "$SHORT_GRAPHS"

  summarize "$SHORT_RESULTS" "$SHORT_GRAPHS" "TEST RAPIDO"
  echo
  ok "Se i grafici in benchmark_folder_clingo/{graphs-native,graphs-prolog,graphs-comparison-native-prolog}/ hanno senso, la pipeline funziona."
  ok "Per la suite completa:  sh 2_run_benchmark_full.sh"
}

main "$@"
