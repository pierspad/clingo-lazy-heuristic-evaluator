#!/usr/bin/env bash
# ============================================================
# Benchmark BSP randomico / multi-seed (analisi di varianza).
#
# A cosa serve: clasp e' sensibile al seed, quindi un singolo run non dice
# nulla sulla stabilita' dei numeri di ricerca (choices/conflicts/solving).
# Questo script ripete le varianti BSP su piu' seed e su piu' opzioni
# randomizzate di clingo, cosi' da poter confrontare la dispersione tra
# varianti. gen_graphs.py --type bsp_random legge il CSV prodotto e disegna
# le curve per-seed (linee sottili) con la media (linea spessa).
#
# Funziona per entrambi i backend (il backend prolog viene attivato
# automaticamente dalla libreria: LAZY_HEURISTIC_BACKEND=prolog).
#
# Uso:
#   ./2_benchmark_bsp_random.sh [native|prolog|both]   (default: native)
#
# Override via ambiente:
#   VARIANTS         varianti BSP da confrontare (default "la lc ga gc")
#   SEEDS            seed da provare           (default "1 2 3")
#   RANDOM_SETTINGS  coppie nome:opzione       (default
#                    "seed_only: rand_freq_0_01:--rand-freq=0.01")
#   N_START N_END N_STEP   range di n          (default 40 100 30)
#   TIMEOUT MODELS         come negli altri benchmark
#   RANDOM_CSV       percorso CSV esplicito (sovrascrive il default per-backend)
# ============================================================
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_bench_lib.sh"

TARGET="${1:-native}"

case "${TARGET}" in
    native|prolog)
        run_bsp_random "${TARGET}"
        ;;
    both)
        run_bsp_random "native"
        # RANDOM_CSV, se passato, vale per UN backend: non riusarlo per due.
        unset RANDOM_CSV || true
        run_bsp_random "prolog"
        ;;
    *)
        echo "Uso: $0 [native|prolog|both]" >&2
        exit 1
        ;;
esac
