#!/bin/bash
set -e

# Nome della directory di lavoro
TARGET_DIR="clingo-modified"

# Rimuove la directory solo se esiste per garantire un ambiente pulito
[ -d "$TARGET_DIR" ] && rm -rf "$TARGET_DIR"

# 1. Clone shallow: scarica solo l'ultimo commit per risparmiare tempo
git clone --depth 1 https://github.com/potassco/clingo.git "$TARGET_DIR"
cd "$TARGET_DIR"

# 2. Inizializzazione shallow dei sottomoduli
# Essenziale per scaricare clasp e le altre dipendenze in modo efficiente
git submodule update --init --recursive --depth 1

# 3. Applicazione della patch per le euristiche
# Assicurati che fix.patch sia nella directory superiore
if [ -f ../fix.patch ]; then
    patch -p1 < ../fix.patch
fi

# 4. Configurazione dell'ambiente di build
mkdir -p build
cd build

# 5. Generazione dei file con Ninja e Clang++ (scelte ottime per lo sviluppo su Arch)
cmake -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER=clang++ ..

# 6. Compilazione
ninja