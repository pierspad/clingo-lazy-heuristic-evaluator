#!/bin/bash
set -e

# Naviga alla cartella di build di clingo-modified partendo da test_folder
cd "$(dirname "$0")/../clingo-modified/build"

# Ricompila il progetto
ninja
echo "Compilazione completata con successo!"
