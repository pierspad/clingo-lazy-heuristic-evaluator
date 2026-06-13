#!/usr/bin/env bash
# Benchmark PUP - backend prolog.
# Esegue tutte le varianti dell'encoding PUP col binario clingo-prolog.
# Override via ambiente: CLINGO_BIN, TIMEOUT, MODELS, VARIANTS, PUP_GLOB.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_bench_lib.sh"
run_pup "prolog"
