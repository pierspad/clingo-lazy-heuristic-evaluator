#!/bin/bash
set -e

TARGET_DIR="clingo-modified"

# Evita di sovrascrivere l'ambiente se è già stato scaricato
if [ -d "$TARGET_DIR" ]; then
    echo "Directory $TARGET_DIR esistente. Setup interrotto per preservare le modifiche locali."
    exit 0
fi

git clone --depth 1 https://github.com/potassco/clingo.git "$TARGET_DIR"
cd "$TARGET_DIR"

git submodule update --init --recursive --depth 1

if [ -f ../fix.patch ]; then
    patch -p1 < ../fix.patch
fi