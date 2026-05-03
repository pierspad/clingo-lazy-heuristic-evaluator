#!/usr/bin/env sh

python3 tools/gen_graphs.py --reset
python3 tools/gen_graphs.py --type bsp
python3 tools/gen_graphs.py --type bsp --exclude bspga


