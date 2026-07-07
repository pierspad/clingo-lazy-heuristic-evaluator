#!/usr/bin/env bash
# ============================================================
# Variante LOCALE di compile_all.sh (quello che gira via sbatch su HPC).
#
# NON viene mai sincronizzato verso l'HPC: pushhpccode lo esclude
# esplicitamente (vedi hpc_sync_functions.zsh, --exclude='/compile_all_local.sh'
# prima di --include='/*.sh').
#
# Differenze rispetto alla versione HPC (compile_all.sh):
#   - niente #SBATCH / niente `module load` Spack: usa il gcc/g++ di sistema
#   - CLEAN_BUILD=0 di default: le build sono INCREMENTALI (ninja si occupa
#     di ricompilare solo cio' che serve). Metti CLEAN_BUILD=1 quando cambi
#     toolchain (versione di gcc/cmake) o quando sospetti una cache CMake
#     corrotta.
#   - le tre build finiscono negli stessi path relativi attesi di default da
#     test_folder/benchmark_folder_clingo/scripts/bench_common.sh
#     (ensure_clingo_bins): clingo-native/build, clingo-prolog/build, e
#     l'installazione di swipl in $HOME/swipl-10. Cosi' 1_run_benchmark_short.sh
#     / 2_run_benchmark_full.sh (e gli script in bench-runs-local/) li trovano
#     senza bisogno di export manuali.
#
# Uso, dalla root di clingo-lazy-heuristics:
#   ./compile_all_local.sh
#   CLEAN_BUILD=1 ./compile_all_local.sh     # forza una ricompilazione pulita
# ============================================================
set -euo pipefail

# Questo script vive DENTRO clingo-lazy-heuristics; swipl-moderno e' un
# sibling della cartella, un livello sopra (stessa convenzione dell'HPC:
# ~/clingo-lazy-heuristics e ~/swipl-moderno sono entrambi sotto $HOME).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWIPL_SRC="$REPO_ROOT/../swipl-moderno/swipl-10.0.2"
SWIPL_PREFIX="$HOME/swipl-10"
CLEAN_BUILD="${CLEAN_BUILD:-0}"

log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }

_prep_build_dir() {
  # mkdir -p e' idempotente; il rm -rf scatta SOLO se CLEAN_BUILD=1.
  local dir="$1"
  if [ "$CLEAN_BUILD" = 1 ]; then
    log "CLEAN_BUILD=1: pulisco $dir"
    rm -rf "$dir"
  fi
  mkdir -p "$dir"
}

log "[1/3] Configurazione e compilazione SWI-Prolog 10 (source: ../swipl-moderno/) ..."
[ -d "$SWIPL_SRC" ] || { echo "Sorgenti assenti: esegui prima ../swipl-moderno/download.sh"; exit 1; }
_prep_build_dir "$SWIPL_SRC/build"
cd "$SWIPL_SRC/build"
cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$SWIPL_PREFIX" \
  -DCMAKE_C_COMPILER=gcc \
  -DCMAKE_CXX_COMPILER=g++ \
  -DINSTALL_DOCUMENTATION=OFF \
  -DSWIPL_PACKAGES_X=OFF -DSWIPL_PACKAGES_JAVA=OFF -DSWIPL_PACKAGES_ODBC=OFF
ninja
ninja install

log "[2/3] Compilazione Clingo Nativo ..."
_prep_build_dir "$REPO_ROOT/clingo-native/build"
cd "$REPO_ROOT/clingo-native/build"
cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja

log "[3/3] Compilazione Clingo Prolog (con backend SWI-Prolog) ..."
_prep_build_dir "$REPO_ROOT/clingo-prolog/build"
cd "$REPO_ROOT/clingo-prolog/build"
cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCLINGO_USE_SWIPL=ON \
  -DCMAKE_PREFIX_PATH="$SWIPL_PREFIX" \
  -DCMAKE_C_COMPILER=gcc \
  -DCMAKE_CXX_COMPILER=g++
ninja

echo
log "COMPILATO CON SUCCESSO (locale)"
log "swipl:         $SWIPL_PREFIX/bin/swipl"
log "clingo-native: $REPO_ROOT/clingo-native/build/bin/clingo"
log "clingo-prolog: $REPO_ROOT/clingo-prolog/build/bin/clingo"
