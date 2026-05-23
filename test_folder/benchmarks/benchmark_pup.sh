#!/usr/bin/env bash
set -euo pipefail

capture_overrides() {
    local name target
    for name in "$@"; do
        if [ "${!name+x}" ]; then
            target="__OVERRIDE_${name}"
            printf -v "${target}" "%s" "${!name}"
        fi
    done
}

apply_overrides() {
    local name source
    for name in "$@"; do
        source="__OVERRIDE_${name}"
        if [ "${!source+x}" ]; then
            printf -v "${name}" "%s" "${!source}"
        fi
    done
}

PUP_CONFIG_VARS=(
    PUP_TIMEOUT_SECONDS
    PUP_REPEATS
    PUP_N_START
    PUP_N_END
    PUP_N_STEP
    PUP_MEM_LIMIT_BYTES
    PUP_MEM_LIMIT_MB
    PUP_MEM_LIMIT_GB
    PUP_CLINGO_EXTRA_ARGS
    PUP_RESULTS_CSV
    PUP_METADATA_FILE
    PUP_FAILURES_FILE
)
capture_overrides "${PUP_CONFIG_VARS[@]}"

PUP_TIMEOUT_SECONDS=180
PUP_REPEATS=1
PUP_N_START=10
PUP_N_END=100
PUP_N_STEP=10

PUP_MEM_LIMIT_BYTES=
PUP_MEM_LIMIT_MB=
PUP_MEM_LIMIT_GB=10
PUP_CLINGO_EXTRA_ARGS=

PUP_RESULTS_CSV="test_folder/results/pup_results.csv"
PUP_METADATA_FILE="test_folder/results/pup_metadata.json"
PUP_FAILURES_FILE="test_folder/results/pup_failures.txt"

apply_overrides "${PUP_CONFIG_VARS[@]}"

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
