#!/usr/bin/env bash
# ============================================================
#  SUITE COMPLETA DISTRIBUITA SU CLUSTER (SLURM).
#
#  Uso, dalla cartella root del repo:
#      bash 4_run_benchmark_hpc.sh
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

# ============================================================
#  COSTANTI MODIFICABILI
# ============================================================
FULL_TIMEOUT=300     # <-- timeout per istanza, in SECONDI
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEST_DIR="$REPO_ROOT/test_folder/benchmark_folder_clingo"

# Caricamento delle funzioni core di btool
# shellcheck disable=SC1091
. "$TEST_DIR/scripts/bench_common.sh"

FULL_OUTPUT="output"
FULL_RS="runscripts/runscript.full.xml"
FULL_RESULTS="results.xml"
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
    [ "$n" -gt 0 ] || die "benchmarks/$fam vuota e nessun backup disponibile"
    ok "$fam: $n istanze"
  done
}

main() {
  log "SUITE COMPLETA CLUSTER — timeout ${FULL_TIMEOUT}s, partizione SLURM"
  
  bootstrap_env
  ensure_runlim
  ensure_clingo_bins
  restore_canonical_instances

  cd "$TEST_DIR"

  log "Derivo il runscript completo per HPC ($FULL_RS) ..."
  derive_runscript \
    "runscripts/runscript.xml" "$FULL_RS" \
    "$FULL_TIMEOUT" "$FULL_OUTPUT" \
    "benchmarks/BSP" "benchmarks/PUP" "benchmarks/HRP" \
    "0"   # <-- 0 indica di NON droppare la configurazione HPC dist-hpc

  log "Generazione dei job distribuiti tramite btool gen ..."
  btool gen -c "$FULL_RS"

  log "Sottomissione dei job alla coda SLURM (partizione 'kr') ..."
  btool run-dist "$FULL_OUTPUT/study-hpc/hpc"

  echo
  ok "I job sono stati sottomessi a SLURM con successo!"
  ok "Usa 'squeue -u \$USER' per monitorare lo stato della coda."
  ok "Una volta completati i calcoli, potrai lanciare la fase di valutazione ed Excel."
}

main "$@"
