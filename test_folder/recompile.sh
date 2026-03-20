#!/bin/bash
set -e

# Naviga alla cartella di build di clingo-modified partendo da test_folder
cd "/home/ribben/Desktop/thesis-clingo/clingo-modified/build"

# Ricompila il progetto
ninja
echo "Compilazione completata con successo!"
