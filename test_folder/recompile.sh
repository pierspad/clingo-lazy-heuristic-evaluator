#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
BUILD_DIR="$SCRIPT_DIR/../clingo-modified/build"

if [ ! -d "$BUILD_DIR" ]; then
    echo "Errore: La directory $BUILD_DIR non esiste. Esegui prima la configurazione con CMake."
    exit 1
fi

cd "$BUILD_DIR"
ninja
echo "Compilazione completata con successo!"