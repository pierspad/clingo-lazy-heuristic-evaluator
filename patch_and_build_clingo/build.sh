#!/bin/bash
set -e

# Path corretto per risalire di una directory
TARGET_DIR="../clingo-modified"

cd "$TARGET_DIR"
mkdir -p build
cd build

if [ ! -f build.ninja ]; then
    cmake -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_COMPILER=clang++ ..
fi

ninja