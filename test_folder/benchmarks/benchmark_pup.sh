#!/usr/bin/env bash
# Stub storico. PUP non e' implementato in questa suite.

set -euo pipefail

# ==============================================================================
# PARAMETRI PUP MODIFICABILI
#
# Questo blocco e' pronto per quando il benchmark PUP verra' implementato. Usa
# il prefisso PUP_* per evitare collisioni con BSP_*.
#
# Override da shell:
#   PUP_TIMEOUT_SECONDS=60 PUP_N_START=10 PUP_N_END=100 ./benchmark_pup.sh
#
# Compatibilita': i vecchi nomi generici TIMEOUT_SECONDS, REPEATS, N_START,
# N_END, N_STEP, MEM_LIMIT_BYTES, MEM_LIMIT_GB e MEM_LIMIT_MB restano fallback.
# Se imposti sia PUP_N_END sia N_END, vince PUP_N_END.
#
# Opzioni clingo future:
#   PUP_CLINGO_EXTRA_ARGS="--init-watches=rnd"
# ==============================================================================
PUP_TIMEOUT_SECONDS="${PUP_TIMEOUT_SECONDS:-${TIMEOUT_SECONDS:-180}}"
PUP_REPEATS="${PUP_REPEATS:-${REPEATS:-1}}"
PUP_N_START="${PUP_N_START:-${N_START:-10}}"
PUP_N_END="${PUP_N_END:-${N_END:-100}}"
PUP_N_STEP="${PUP_N_STEP:-${N_STEP:-10}}"

PUP_MEM_LIMIT_BYTES="${PUP_MEM_LIMIT_BYTES:-${MEM_LIMIT_BYTES:-}}"
PUP_MEM_LIMIT_MB="${PUP_MEM_LIMIT_MB:-${MEM_LIMIT_MB:-}}"
PUP_MEM_LIMIT_GB="${PUP_MEM_LIMIT_GB:-${MEM_LIMIT_GB:-10}}"
PUP_CLINGO_EXTRA_ARGS="${PUP_CLINGO_EXTRA_ARGS:-${CLINGO_EXTRA_ARGS:-}}"

PUP_RESULTS_CSV="${PUP_RESULTS_CSV:-test_folder/results/pup_results.csv}"
PUP_METADATA_FILE="${PUP_METADATA_FILE:-test_folder/results/pup_metadata.json}"
PUP_FAILURES_FILE="${PUP_FAILURES_FILE:-test_folder/results/pup_failures.txt}"
# ==============================================================================

export PUP_TIMEOUT_SECONDS
export PUP_REPEATS
export PUP_N_START
export PUP_N_END
export PUP_N_STEP
export PUP_MEM_LIMIT_BYTES
export PUP_MEM_LIMIT_MB
export PUP_MEM_LIMIT_GB
export PUP_CLINGO_EXTRA_ARGS
export PUP_RESULTS_CSV
export PUP_METADATA_FILE
export PUP_FAILURES_FILE

echo "================================================================"
echo "  Benchmark PUP disabilitato (nessuna istanza/encoding presente)"
echo "  Parametri PUP gia' separati con prefisso PUP_* per uso futuro"
echo "================================================================"

exit 0
