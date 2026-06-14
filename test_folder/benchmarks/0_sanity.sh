#!/usr/bin/env bash
# ============================================================
# Sanity-check di correttezza da lanciare PRIMA dei benchmark.
# Verifica che le euristiche non cambino le soluzioni e che il backend
# SWI-Prolog sia effettivamente attivo. Vedi tools/check_equivalence.py.
#
# Uso:
#   ./0_sanity.sh                 # native + prolog
#   ./0_sanity.sh --backends native
#   ./0_sanity.sh --strict-guidance
# Tutti gli argomenti vengono inoltrati a check_equivalence.py.
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
exec "${PYTHON_BIN}" "${TEST_ROOT}/tools/check_equivalence.py" "$@"
