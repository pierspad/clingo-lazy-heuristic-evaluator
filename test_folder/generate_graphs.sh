#!/usr/bin/env sh

PYTHON_BIN="${PYTHON_BIN:-python3}"

"${PYTHON_BIN}" tools/gen_graphs.py --reset
"${PYTHON_BIN}" tools/gen_graphs.py --type bsp
"${PYTHON_BIN}" tools/gen_graphs.py --type bsp --exclude bsplaco

# "${PYTHON_BIN}" tools/gen_graphs.py --type bsp --exclude bspga

