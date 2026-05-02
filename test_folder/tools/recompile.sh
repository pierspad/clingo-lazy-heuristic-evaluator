#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/clingo-modified/build"

if [ ! -d "$BUILD_DIR" ]; then
    echo "Errore: La directory $BUILD_DIR non esiste. Esegui prima la configurazione con CMake."
    exit 1
fi

cd "$BUILD_DIR"

if [ -f CMakeCache.txt ] && grep -q '^CMAKE_BUILD_TYPE:STRING=Debug$' CMakeCache.txt; then
    echo "Avviso: questa build CMake e' configurata in Debug, quindi non usera' -O3."
    echo "Riconfigura con: cmake -S ../ -B . -G Ninja -DCMAKE_BUILD_TYPE=Release"
fi

ninja
echo "Compilazione completata con successo!"
