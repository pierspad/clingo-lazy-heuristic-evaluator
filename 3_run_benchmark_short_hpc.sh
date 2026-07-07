#!/usr/bin/env bash
# ============================================================
#  SMOKE TEST SU CLUSTER (SLURM) - Nome file: 3_run_benchmark_short_hpc.sh
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

# Questo script chiama ensure_runlim/ensure_clingo_bins (bench_common.sh),
# che se il binario manca lo (ri)compilano SUL NODO DA CUI VENGONO ESEGUITE.
# Lanciato a mano sul login node, quel binario finisce linkato con la glibc
# del login node — la stessa causa gia' diagnosticata per lo "smoke test
# fantasma" (runlim compilato sul login node, exec fallito sui compute node,
# nessun errore visibile perche' seq-generic.sh non ha `set -e`). Per non
# ripetere l'errore: se non siamo gia' dentro un'allocazione SLURM (nessun
# $SLURM_JOB_ID), ci rilanciamo da soli su un compute node via `srun`, prima
# di toccare qualunque compilazione. btool gen/run-dist funzionano
# normalmente anche da dentro un job SLURM (sottomissione annidata supportata).
if [ -z "${SLURM_JOB_ID:-}" ]; then
  echo "==> Non sono su un compute node: mi rilancio via 'srun --partition=kr' ..."
  exec srun --partition=kr --ntasks=1 --cpus-per-task=4 --time=00:30:00 bash "$0" "$@"
fi

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

# Percorsi assoluti risolti alla radice operativa
SHORT_RS_IN="$TEST_DIR/runscripts/runscript.xml"
SHORT_RS_OUT="$TEST_DIR/runscripts/runscript.short_hpc.xml"

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
  rm -rf "$TEST_DIR/$SHORT_BENCH"; mkdir -p "$TEST_DIR/$SHORT_BENCH"

  python3 "$TEST_DIR/tools/gen_bsp_instances.py" \
    --out "$TEST_DIR/$SHORT_BENCH/BSP" --start "$SHORT_BSP_START" --end "$SHORT_BSP_END" --step 1 --clean \
    || die "generazione istanze BSP short fallita"

  local pup_src="$TEST_DIR/benchmarks.bak/PUP"; [ -d "$pup_src" ] || pup_src="$TEST_DIR/benchmarks/PUP"
  local hrp_src="$TEST_DIR/benchmarks.bak/HRP"; [ -d "$hrp_src" ] || hrp_src="$TEST_DIR/benchmarks/HRP"
  copy_smallest "$pup_src" "$TEST_DIR/$SHORT_BENCH/PUP" "$SHORT_PUP_COUNT"
  copy_smallest "$hrp_src" "$TEST_DIR/$SHORT_BENCH/HRP" "$SHORT_HRP_COUNT"
}

main() {
  log "SMOKE TEST CLUSTER — timeout ${TIMEOUT}s, subset isolato"
  bootstrap_env
  ensure_runlim
  ensure_clingo_bins
  build_short_subset

  cd "$TEST_DIR"

  log "Derivo il runscript short per HPC ($SHORT_RS_OUT) ..."
  derive_runscript \
    "$SHORT_RS_IN" "$SHORT_RS_OUT" \
    "$TIMEOUT" "$SHORT_OUTPUT" \
    "$SHORT_BENCH/BSP" "$SHORT_BENCH/PUP" "$SHORT_BENCH/HRP" \
    "0"

  log "btool gen -c per cluster ..."
  btool gen -c "$SHORT_RS_OUT"

  log "Invio dei mini-job a SLURM (3 project paralleli: bsp/pup/hrp) ..."
  local proj dispatched=0
  for proj in study-hpc-bsp study-hpc-pup study-hpc-hrp; do
    local d="$SHORT_OUTPUT/$proj/hpc"
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
  ok "Smoke test sottomesso ($dispatched project)! Controlla con 'squeue -u \$USER' o 'sh wait_hpc.sh'."
}

main "$@"