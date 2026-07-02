#!/bin/bash
set -e

# Ricompila uno (o entrambi) i backend clingo.
# Uso:
#   recompile.sh [native|prolog|all]   (default: all)
# Override: BUILD_DIR per puntare a una build specifica.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TARGET="${1:-all}"

build_one() {
    local backend="$1"
    local build_dir="${BUILD_DIR:-$REPO_ROOT/clingo-${backend}/build}"

    if [ ! -d "$build_dir" ]; then
        echo "Errore: la directory $build_dir non esiste. Configura prima con CMake:"
        echo "  cmake -S $REPO_ROOT/clingo-${backend} -B $build_dir -G Ninja -DCMAKE_BUILD_TYPE=Release"
        exit 1
    fi

    cd "$build_dir"
    if [ -f CMakeCache.txt ] && grep -q '^CMAKE_BUILD_TYPE:STRING=Debug$' CMakeCache.txt; then
        echo "Avviso: build CMake di clingo-${backend} in Debug (niente -O3)."
        echo "Riconfigura con: cmake -S ../ -B . -G Ninja -DCMAKE_BUILD_TYPE=Release"
    fi
    echo ">> Compilo clingo-${backend} in ${build_dir}"
    ninja
    echo ">> clingo-${backend}: compilazione completata."
}

case "$TARGET" in
    native) build_one native ;;
    prolog) build_one prolog ;;
    all)    build_one native; build_one prolog ;;
    *) echo "Uso: $0 [native|prolog|all]"; exit 1 ;;
esac

echo "Fatto."
