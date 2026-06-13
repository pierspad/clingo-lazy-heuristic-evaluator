#!/usr/bin/env bash
# Benchmark BSP - backend native.
# Esegue tutte le varianti dell'encoding BSP col binario clingo-native.
# Override via ambiente: CLINGO_BIN, TIMEOUT, MODELS, VARIANTS, N_START N_END N_STEP.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_bench_lib.sh"
run_bsp "native"
