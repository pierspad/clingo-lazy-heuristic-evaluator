#!/usr/bin/env bash
# ============================================================
#  SMOKE TEST SU CLUSTER (SLURM)
#  Verifica la sottomissione e i runscript distribuiti su un subset ridotto.
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

# ============================================================
#  COSTANTI MODIFICABILI
# ============================================================
TIMEOUT=15            # <-- timeout breve per test
SHORT_BSP_START=3     
SHORT_BSP_END=5
SHORT_PUP_COUNT=2     
SHORT_HRP_COUNT=2
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEST_DIR="$REPO_ROOT/test_folder/benchmark_folder_clingo"
# shellcheck disable=SC1091
. "$TEST_DIR/scripts/bench_common.sh"

SHORT_BENCH="benchmarks/_short_hpc"
SHORT_OUTPUT="output-short-hpc"
SHORT_RS="runscripts/runscript.short_hpc.xml"

copy_smallest() {
  local src="$1" dst="$2" count="$3"
  mkdir -p "$dst"
  [ -d "$src" ] || { warn "sorgente istanze assente: $src"; return 0; }
  ls "$src" 2>/dev/null | sort -t- -k2 -n | head -n "$count" | while read -r f; do
    cp -f "$src/$f" "$dst/$f"
  done
}

build_short_subset() {
  log "Costruisco il mini-subset isolato per HPC in $SHORT_BENCH/ ..."
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
  log "SMOKE TEST CLUSTER — timeout ${TIMEOUT}s, subset isolato"
  bootstrap_env
  ensure_runlim
  ensure_clingo_bins
  build_short_subset

  cd "$TEST_DIR"

  log "Derivo il runscript short per HPC ($SHORT_RS) ..."
  derive_runscript \
    "runscripts/runscript.xml" "$SHORT_RS" \
    "$TIMEOUT" "$SHORT_OUTPUT" \
    "$SHORT_BENCH/BSP" "$SHORT_BENCH/PUP" "$SHORT_BENCH/HRP" \
    "0"   # <-- 0 per includere configurazione HPC

  log "btool gen -c per cluster ..."
  btool gen -c "$SHORT_RS"

  log "Invio dei mini-job a SLURM ..."
  btool run-dist "$SHORT_OUTPUT/study-hpc/hpc"
  
  echo
  ok "Smoke test sottomesso! Controlla con 'squeue -u \$USER'."
  ok "Quando la coda si svuota, faremo lo script 4 per raccogliere i dati e plottare."
}

main "$@"
