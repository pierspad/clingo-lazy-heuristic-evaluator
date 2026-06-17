#!/usr/bin/env bash
# Benchmark PUP - backend native.
# Esegue tutte le varianti dell'encoding PUP col binario clingo-native.
# Override via ambiente: CLINGO_BIN, TIMEOUT, MODELS, VARIANTS, PUP_GLOB.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_bench_lib.sh"
run_pup "native"
