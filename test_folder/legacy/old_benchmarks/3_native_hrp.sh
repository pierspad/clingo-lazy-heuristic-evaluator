#!/usr/bin/env bash
# Benchmark HRP - backend native.
# Esegue tutte le varianti dell'encoding HRP col binario clingo-native.
# Override via ambiente: CLINGO_BIN, TIMEOUT, MODELS, VARIANTS, HRP_GLOB.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_bench_lib.sh"
run_hrp "native"
