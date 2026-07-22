#!/usr/bin/env bash
# ============================================================
#  MIRROR LOCALE della suite completa HPC (4_run_benchmark_hpc.sh in root).
#
#  Stessi parametri della full HPC (timeout 600s, set canonico di istanze),
#  ma eseguita via run_btool_pipeline (run-seq) invece che via SLURM/btool
#  run-dist. In pratica coincide con 2_run_benchmark_full.sh: la teniamo come
#  file separato solo per rispecchiare 1:1 i nomi degli script HPC e per non
#  sovrascrivere gli output di una eventuale 2_run_benchmark_full.sh già in
#  corso (output/risultati separati: vedi FULL_OUTPUT sotto).
#
#  Uso, da questa cartella:
#      sh 4_run_benchmark_hpc.sh
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

FULL_TIMEOUT=600  # 2026-07-22: allineato a 4_run_benchmark_hpc.sh in root

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
TEST_DIR="$REPO_ROOT/test_folder/benchmark_folder_clingo"
# shellcheck disable=SC1091
. "$TEST_DIR/scripts/bench_common.sh"

FULL_OUTPUT="output-hpc-mirror"
FULL_RS="runscripts/runscript.full_hpc_mirror.xml"
FULL_RESULTS="results-hpc-mirror.xml"
FULL_GRAPHS=".."

restore_canonical_instances() {
  local fam n have_bak=0
  [ -d benchmarks.bak ] && have_bak=1
  if [ "$have_bak" = 1 ]; then
    log "Ripristino il set canonico da benchmarks.bak/ ..."
  else
    warn "benchmarks.bak/ assente: uso il set gia' versionato in benchmarks/"
  fi
  for fam in BSP PUP HRP; do
    if [ "$have_bak" = 1 ] && [ -d "benchmarks.bak/$fam" ]; then
      mkdir -p "benchmarks/$fam"
      cp -f benchmarks.bak/"$fam"/* "benchmarks/$fam"/ 2>/dev/null || true
    fi
    n=$(ls "benchmarks/$fam" 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] || die "benchmarks/$fam vuota e nessun backup disponibile: non ho istanze $fam"
    ok "$fam: $n istanze"
  done
}

main() {
  log "SUITE COMPLETA — mirror locale dei parametri HPC (timeout ${FULL_TIMEOUT}s)"
  bootstrap_env
  ensure_runlim
  ensure_clingo_bins
  restore_canonical_instances

  log "Derivo il runscript ($FULL_RS) ..."
  derive_runscript \
    "runscripts/runscript.xml" "$FULL_RS" \
    "$FULL_TIMEOUT" "$FULL_OUTPUT" \
    "benchmarks/BSP" "benchmarks/PUP" "benchmarks/HRP" \
    "1"

  run_btool_pipeline "$FULL_RS" "$FULL_OUTPUT" "study-local" "local" \
    "$FULL_RESULTS" "$FULL_GRAPHS"

  summarize "$FULL_RESULTS" "$FULL_GRAPHS" "SUITE COMPLETA (mirror HPC)"
  echo
  ok "Attenzione: con timeout 300s e il set canonico completo questo può richiedere MOLTO tempo su una macchina locale (2 core in un sandbox, di più su un laptop reale ma comunque niente cluster). Valuta prima 3_run_benchmark_short_hpc.sh."
}

main "$@"
