#!/usr/bin/env bash
# ============================================================
#  SUITE COMPLETA di benchmark.
#
#  Uso, dalla cartella root del repo:
#      sh 2_run_benchmark_full.sh
#
#  Cosa fa: prepara l'ambiente (venv/btool/runlim/clingo), ripristina il set
#  canonico di istanze da benchmarks.bak/ (BSP n=3..30, PUP 20..200,
#  HRP 2..20), esegue tutto in locale e produce results.xml + graphs/.
#
#  Idempotente: i run gia' completati (.finished) vengono saltati, quindi
#  puoi rilanciarlo per riprendere. Per rifare TUTTO da zero:
#      FORCE=1 sh 2_run_benchmark_full.sh
#
#  Per forzare la ricompilazione dei binari clingo:
#      REBUILD_CLINGO=1 sh 2_run_benchmark_full.sh
# ============================================================

# >>> se lanciato con `sh`, ri-eseguo sotto bash (servono feature bash) <<<
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

# ============================================================
#  COSTANTI MODIFICABILI
# ============================================================
FULL_TIMEOUT=300     # <-- timeout per istanza, in SECONDI (modifica qui)
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# La macchina btool (programs/, runscripts/, tools/, benchmarks/, .venv, ...)
# vive ora in test_folder/benchmark_folder_clingo/. cwd di btool = questa.
TEST_DIR="$REPO_ROOT/test_folder/benchmark_folder_clingo"
# shellcheck disable=SC1091
. "$TEST_DIR/scripts/bench_common.sh"

FULL_OUTPUT="output"
FULL_RS="runscripts/runscript.full.xml"
FULL_RESULTS="results.xml"
# I grafici "veri" vanno UN LIVELLO SOPRA (test_folder): graphs-native/,
# graphs-prolog/, graphs-comparison-native-prolog/ fuori dalla cartella btool.
FULL_GRAPHS=".."

# Ripristina il set canonico di istanze in benchmarks/.
# Fonte primaria: benchmarks.bak/ (backup locale, utile per annullare edit
# manuali). Se assente — es. clone pulito — il set canonico e' comunque gia'
# versionato in benchmarks/ stesso, quindi si procede con quello.
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

# ============================================================
main() {
  log "SUITE COMPLETA — timeout ${FULL_TIMEOUT}s, set canonico (graphs/)"
  bootstrap_env
  ensure_runlim
  ensure_clingo_bins
  restore_canonical_instances

  log "Derivo il runscript completo ($FULL_RS) ..."
  derive_runscript \
    "runscripts/runscript.xml" "$FULL_RS" \
    "$FULL_TIMEOUT" "$FULL_OUTPUT" \
    "benchmarks/BSP" "benchmarks/PUP" "benchmarks/HRP" \
    "1"   # drop_hpc: questo script esegue solo in locale

  run_btool_pipeline "$FULL_RS" "$FULL_OUTPUT" "study-local" "local" \
    "$FULL_RESULTS" "$FULL_GRAPHS"

  summarize "$FULL_RESULTS" "$FULL_GRAPHS" "SUITE COMPLETA"
  echo
  ok "Risultati in $FULL_RESULTS, foglio in $FULL_OUTPUT/results.xlsx."
  ok "Grafici in test_folder/{graphs-native,graphs-prolog,graphs-comparison-native-prolog}/"
}

main "$@"
