#!/usr/bin/env bash
# ============================================================
#  SUITE COMPLETA DISTRIBUITA SU CLUSTER (SLURM) - Nome file: 4_run_benchmark_hpc.sh
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

# Stesso motivo del guard in 3_run_benchmark_short_hpc.sh: ensure_runlim/
# ensure_clingo_bins (ri)compilano sul nodo da cui vengono chiamate. Se
# lanciato a mano sul login node, rischia lo stesso mismatch di glibc gia'
# diagnosticato per lo "smoke test fantasma". Ci rilanciamo su un compute
# node via srun prima di toccare qualunque compilazione; la sottomissione
# dei job distjob (btool run-dist) funziona normalmente anche da li'.
if [ -z "${SLURM_JOB_ID:-}" ]; then
  echo "==> Non sono su un compute node: mi rilancio via 'srun --partition=kr' ..."
  exec srun --partition=kr --ntasks=1 --cpus-per-task=4 --time=00:30:00 bash "$0" "$@"
fi

# ============================================================
#  COSTANTI MODIFICABILI
# ============================================================
FULL_TIMEOUT=600
# 2026-07-22: alzato da 300 a 600. A 300s 'gc' su BSP timeoutava GIA' a
# N=120 (227s = 76% budget) e gc_noheur/ga_weak erano al 71-77%; col range
# BSP esteso a 200 (v. benchmarks/BSP/) sarebbe stato ancora piu' stretto,
# senza dare nuova informazione (solo altri timeout, non nuove separazioni
# tra le varianti). 600s combacia anche con quanto il <distjob> di
# runscript.xml dichiarava gia' (ma che FULL_TIMEOUT=300 sovrascriveva).
# v. [[project_graphs_analysis_2026-07-22]].
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

  ensure_no_pending_dist_jobs
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

  log "Sottomissione dei job alla coda SLURM (3 project paralleli: bsp/pup/hrp, partizione 'kr') ..."
  local proj dispatched=0
  for proj in study-hpc-bsp study-hpc-pup study-hpc-hrp; do
    local d="$FULL_OUTPUT/$proj/hpc"
    if [ -d "$d" ]; then
      log "  -> dispatch $proj ($d)"
      btool run-dist "$d"
      dispatched=$((dispatched + 1))
    else
      warn "cartella non trovata, salto: $d"
    fi
  done
  [ "$dispatched" -gt 0 ] || die "nessun project dispacciato: controlla l'output di 'btool gen -c' sopra"

  echo
  ok "I job sono stati sottomessi a SLURM con successo ($dispatched project concorrenti)! Monitora con 'squeue -u \$USER' o 'sh wait_hpc.sh'."
}

main "$@"