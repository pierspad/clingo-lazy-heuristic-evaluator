#!/usr/bin/env bash
# ============================================================
#  VALUTAZIONE/REPLOT LOCALE (5_evaluate_hpc.sh in root, adattato).
#
#  Rispetto all'originale HPC:
#    - niente attesa/controllo squeue (non c'e' SLURM in locale)
#    - niente filtro XML "tieni solo study-hpc" (qui il progetto e' sempre
#      study-local, generato da drop_hpc=1 negli script 3/4 di questa cartella)
#    - NON rilancia i solve: rilegge solo i run gia' .finished e rigenera
#      xlsx + grafici. Utile per iterare su tools/plot_results.py (es. i bug
#      noti: tabella verdetto vuota, tick "0/-0" sull'asse memoria) senza
#      rifare l'intera suite.
#    - passa --ground-counts se il CSV esiste, cosa che l'originale
#      5_evaluate_hpc.sh non faceva (vedi bug §8.4 dell'audit).
#
#  Uso, da questa cartella:
#      sh 5_evaluate_hpc.sh
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
TEST_DIR="$REPO_ROOT/test_folder/benchmark_folder_clingo"
# shellcheck disable=SC1091
. "$TEST_DIR/scripts/bench_common.sh"

main() {
  log "VALUTAZIONE/REPLOT LOCALE (nessun re-run dei solve)"
  cd "$TEST_DIR"
  bootstrap_env

  local VENV_BTOOL="$TEST_DIR/.venv/bin/btool"
  local VENV_PYTHON="$TEST_DIR/.venv/bin/python3"

  local RUNSCRIPT="" OUTPUT_DIR="" RESULTS=""
  if [ -f "runscripts/runscript.full_hpc_mirror.xml" ]; then
    log "Rilevato runscript: full_hpc_mirror (script 4 di questa cartella)."
    RUNSCRIPT="runscripts/runscript.full_hpc_mirror.xml"
    OUTPUT_DIR="output-hpc-mirror"; RESULTS="results-hpc-mirror.xml"
  elif [ -f "runscripts/runscript.short_hpc_mirror.xml" ]; then
    log "Rilevato runscript: short_hpc_mirror (script 3 di questa cartella)."
    RUNSCRIPT="runscripts/runscript.short_hpc_mirror.xml"
    OUTPUT_DIR="output-short-hpc-mirror"; RESULTS="results-short-hpc-mirror.xml"
  elif [ -f "runscripts/runscript.full.xml" ]; then
    log "Rilevato runscript: full (2_run_benchmark_full.sh)."
    RUNSCRIPT="runscripts/runscript.full.xml"
    OUTPUT_DIR="output"; RESULTS="results.xml"
  elif [ -f "runscripts/runscript.short.xml" ]; then
    log "Rilevato runscript: short (1_run_benchmark_short.sh)."
    RUNSCRIPT="runscripts/runscript.short.xml"
    OUTPUT_DIR="output-short"; RESULTS="results-short.xml"
  else
    die "Nessun runscript locale trovato in 'runscripts/'. Lancia prima uno tra 1/2/3/4."
  fi

  log "Raccolta risultati -> $RESULTS ..."
  "$VENV_BTOOL" eval "$RUNSCRIPT" > "$RESULTS"
  ok "$RESULTS generato."

  log "Excel -> $OUTPUT_DIR/results.xlsx ..."
  "$VENV_BTOOL" conv -m all -o "$OUTPUT_DIR/results.xlsx" "$RESULTS" \
    && ok "xlsx generato." || warn "conv xlsx fallita, proseguo coi grafici"

  local gc_arg=()
  [ -f "$OUTPUT_DIR/ground_counts.csv" ] && gc_arg=(--ground-counts "$OUTPUT_DIR/ground_counts.csv")
  log "Grafici -> .. /{graphs-native,graphs-prolog,graphs-comparison-native-prolog}/ ..."
  PYTHONPATH="" "$VENV_PYTHON" tools/plot_results.py --results "$RESULTS" --machine local \
    --out-base .. "${gc_arg[@]}"

  echo
  ok "Fatto. Dati in $RESULTS, Excel in $OUTPUT_DIR/results.xlsx, grafici in test_folder/."
}

main "$@"
