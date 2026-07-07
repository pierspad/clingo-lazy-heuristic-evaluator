#!/usr/bin/env bash
# ============================================================
#  MIRROR LOCALE dello smoke test HPC (3_run_benchmark_short_hpc.sh in root).
#
#  Riusa ESATTAMENTE gli stessi parametri del subset che va sul cluster
#  (BSP n=3..5, 2 istanze PUP + 2 HRP, timeout 15s) ma li esegue in locale
#  via run_btool_pipeline (run-seq), non via SLURM/btool run-dist. Serve a
#  validare la stessa identica selezione di istanze prima di sottomettere
#  sul cluster, con i binari compilati da compile_all.local.sh.
#
#  Uso, da questa cartella:
#      sh 3_run_benchmark_short_hpc.sh
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

# ============================================================
#  COSTANTI — tenute IDENTICHE a quelle di 3_run_benchmark_short_hpc.sh
#  in root. Se modifichi quelle, modifica anche queste per restare comparabili.
# ============================================================
TIMEOUT=15
SHORT_BSP_START=3
SHORT_BSP_END=5
SHORT_PUP_COUNT=2
SHORT_HRP_COUNT=2
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
TEST_DIR="$REPO_ROOT/test_folder/benchmark_folder_clingo"
# shellcheck disable=SC1091
. "$TEST_DIR/scripts/bench_common.sh"

SHORT_BENCH="benchmarks/_short_hpc_mirror"
SHORT_OUTPUT="output-short-hpc-mirror"
SHORT_RS="runscripts/runscript.short_hpc_mirror.xml"
SHORT_RESULTS="results-short-hpc-mirror.xml"
SHORT_GRAPHS="."

copy_smallest() {
  local src="$1" dst="$2" count="$3"
  mkdir -p "$dst"
  [ -d "$src" ] || { warn "sorgente istanze assente: $src"; return 0; }
  ls "$src" 2>/dev/null | sort -t- -k2 -n | head -n "$count" | while read -r f; do
    cp -f "$src/$f" "$dst/$f"
  done
}

build_short_subset() {
  log "Costruisco il mini-subset (identico a quello HPC) in $SHORT_BENCH/ ..."
  rm -rf "$SHORT_BENCH"; mkdir -p "$SHORT_BENCH"

  python3 tools/gen_bsp_instances.py \
    --out "$SHORT_BENCH/BSP" --start "$SHORT_BSP_START" --end "$SHORT_BSP_END" --step 1 --clean \
    || die "generazione istanze BSP short fallita"

  local pup_src="benchmarks.bak/PUP"; [ -d "$pup_src" ] || pup_src="benchmarks/PUP"
  local hrp_src="benchmarks.bak/HRP"; [ -d "$hrp_src" ] || hrp_src="benchmarks/HRP"
  copy_smallest "$pup_src" "$SHORT_BENCH/PUP" "$SHORT_PUP_COUNT"
  copy_smallest "$hrp_src" "$SHORT_BENCH/HRP" "$SHORT_HRP_COUNT"
}

main() {
  log "SMOKE TEST — mirror locale dei parametri HPC (timeout ${TIMEOUT}s)"
  bootstrap_env
  ensure_runlim
  ensure_clingo_bins
  build_short_subset

  log "Derivo il runscript ($SHORT_RS) ..."
  derive_runscript \
    "runscripts/runscript.xml" "$SHORT_RS" \
    "$TIMEOUT" "$SHORT_OUTPUT" \
    "$SHORT_BENCH/BSP" "$SHORT_BENCH/PUP" "$SHORT_BENCH/HRP" \
    "1"   # drop_hpc: qui giriamo SEMPRE in locale, anche se il subset mima l'HPC

  run_btool_pipeline "$SHORT_RS" "$SHORT_OUTPUT" "study-local" "local" \
    "$SHORT_RESULTS" "$SHORT_GRAPHS"

  summarize "$SHORT_RESULTS" "$SHORT_GRAPHS" "SMOKE TEST (mirror HPC)"
  echo
  ok "Se questo gira pulito, la stessa selezione di istanze dovrebbe girare pulita anche su HPC."
  ok "Se invece qui le varianti la/lc del backend Prolog falliscono ANCHE in locale, il problema è nel codice, non nell'ambiente cluster."
}

main "$@"
