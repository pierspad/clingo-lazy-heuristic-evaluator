#!/usr/bin/env bash
# ============================================================
#  SUITE COMPLETA DISTRIBUITA SU CLUSTER (SLURM) - Nome file: 4_run_benchmark_hpc.sh
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

# ============================================================
#  COSTANTI MODIFICABILI
# ============================================================
FULL_TIMEOUT=300     
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEST_DIR="$REPO_ROOT/test_folder/benchmark_folder_clingo"

# shellcheck disable=SC1091
. "$TEST_DIR/scripts/bench_common.sh"

FULL_OUTPUT="output"
FULL_RS_IN="$TEST_DIR/runscripts/runscript.xml"
FULL_RS_OUT="$TEST_DIR/runscripts/runscript.full.xml"

restore_canonical_instances() {
  local fam n have_bak=0
  [ -d "$TEST_DIR/benchmarks.bak" ] && have_bak=1
  for fam in BSP PUP HRP; do
    if [ "$have_bak" = 1 ] && [ -d "$TEST_DIR/benchmarks.bak/$fam" ]; then
      mkdir -p "$TEST_DIR/benchmarks/$fam"
      cp -f "$TEST_DIR/benchmarks.bak/$fam"/* "$TEST_DIR/benchmarks/$fam"/ 2>/dev/null || true
    fi
    n=$(ls "$TEST_DIR/benchmarks/$fam" 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] || die "benchmarks/$fam vuota e nessun backup disponibile"
  done
}

main() {
  log "SUITE COMPLETA CLUSTER — timeout ${FULL_TIMEOUT}s, partizione SLURM"
  
  bootstrap_env
  ensure_runlim
  ensure_clingo_bins
  restore_canonical_instances

  cd "$TEST_DIR"

  log "Derivo il runscript completo per HPC ($FULL_RS_OUT) ..."
  derive_runscript \
    "$FULL_RS_IN" "$FULL_RS_OUT" \
    "$FULL_TIMEOUT" "$FULL_OUTPUT" \
    "benchmarks/BSP" "benchmarks/PUP" "benchmarks/HRP" \
    "0"

  log "Generazione dei job distribuiti tramite btool gen ..."
  btool gen -c "$FULL_RS_OUT"

  log "Sottomissione dei job alla coda SLURM (partizione 'kr') ..."
  btool run-dist "$FULL_OUTPUT/study-hpc/hpc"

  echo
  ok "I job sono stati sottomessi a SLURM con successo! Monitora con 'squeue -u \$USER'."
}

main "$@"