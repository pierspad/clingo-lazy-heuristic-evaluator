#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TARGET_DIR="${SCRIPT_DIR}/../clingo-modified"

cd "$TARGET_DIR"
mkdir -p build
cd build

if [ ! -f build.ninja ]; then
    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++ ..
fi

ninja
