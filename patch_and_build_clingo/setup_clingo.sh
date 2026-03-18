#!/bin/bash
set -e

# 1. Clone shallow della repository
git clone --depth 1 https://github.com/potassco/clingo.git clingo-repo
cd clingo-repo

# 2. Inizializzazione dei sottomoduli
git submodule update --init --recursive

# 3. Applicazione della patch
patch -p1 < ../fix.patch

# 4. Creazione dell'ambiente di compilazione
mkdir -p build
cd build

# 5. Configurazione e generazione dei file di build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER=clang++ ..

# 6. Compilazione
ninja