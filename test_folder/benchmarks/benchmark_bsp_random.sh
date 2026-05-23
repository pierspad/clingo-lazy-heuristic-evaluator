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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BSP_RANDOM_CONFIG_VARS=(
    BSP_VARIANTS
    BSP_REPEATS
    BSP_N_START
    BSP_N_END
    BSP_N_STEP
    BSP_USE_SEED
    BSP_RANDOM_SETTINGS
    BSP_RESULTS_CSV
    BSP_METADATA_FILE
    BSP_FAILURES_FILE
)
capture_overrides "${BSP_RANDOM_CONFIG_VARS[@]}"

BSP_VARIANTS="la lc ga gc"
BSP_REPEATS=3
BSP_N_START=40
BSP_N_END=100
BSP_N_STEP=30
BSP_USE_SEED=1
BSP_RANDOM_SETTINGS="seed_only: rand_freq_0_01:--rand-freq=0.01"

BSP_RESULTS_CSV="${TEST_ROOT}/results/bsp_random_results.csv"
BSP_METADATA_FILE="${TEST_ROOT}/results/run_random_metadata.json"
BSP_FAILURES_FILE="${TEST_ROOT}/results/bsp_random_failures.txt"

apply_overrides "${BSP_RANDOM_CONFIG_VARS[@]}"

export BSP_VARIANTS
export BSP_REPEATS
export BSP_N_START
export BSP_N_END
export BSP_N_STEP
export BSP_USE_SEED
export BSP_RANDOM_SETTINGS
export BSP_RESULTS_CSV
export BSP_METADATA_FILE
export BSP_FAILURES_FILE

exec "${SCRIPT_DIR}/benchmark_bsp.sh" "$@"
