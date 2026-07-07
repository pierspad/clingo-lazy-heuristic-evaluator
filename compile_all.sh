#!/usr/bin/env bash
#SBATCH --partition=kr
#SBATCH --job-name=compile_clingo_swipl
#SBATCH --output=compile_%j.log
#SBATCH --error=compile_%j.log
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:45:00

set -euo pipefail

# CLEAN_BUILD=1 forza un rm -rf delle build/ prima di riconfigurare (utile
# solo quando cambi versione dei moduli Spack/gcc/cmake, o sospetti una
# CMakeCache corrotta da un mix di toolchain — vedi "keepinmind" per un
# precedente reale). Di default e' 0: le build sono incrementali, ninja
# ricompila solo cio' che serve, molto piu' veloce sui run successivi.
# Uso: sbatch --export=CLEAN_BUILD=1 compile_all.sh
CLEAN_BUILD="${CLEAN_BUILD:-0}"

_prep_build_dir() {
  local dir="$1"
  if [ "$CLEAN_BUILD" = 1 ]; then
    echo "CLEAN_BUILD=1: pulisco $dir"
    rm -rf "$dir"
  fi
  mkdir -p "$dir"
}

echo "==> [1/5] Caricamento moduli Spack..."
module load cmake/3.31.11-gcc-12.5.0-6sfht6u gcc/12.5.0-gcc-8.3.0-3i7iqwe ninja

echo "==> [2/5] Configurazione e compilazione SWI-Prolog 10..."
cd ~/swipl-moderno/swipl-10.0.2
_prep_build_dir build
cd build
export PKG_CONFIG_PATH=$HOME/swipl-10/share/pkgconfig:${PKG_CONFIG_PATH:-}
cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$HOME/swipl-10 \
  -DCMAKE_C_COMPILER=gcc \
  -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_AR=/usr/bin/ar \
  -DCMAKE_RANLIB=/usr/bin/ranlib \
  -DINSTALL_DOCUMENTATION=OFF \
  -DSWIPL_PACKAGES_X=OFF -DSWIPL_PACKAGES_JAVA=OFF -DSWIPL_PACKAGES_ODBC=OFF

ninja -j ${SLURM_CPUS_PER_TASK:-2}
ninja install

echo "==> [3/5] Esportazione PATH locale per Clingo..."
export PATH=$HOME/swipl-10/bin:$PATH

echo "==> [4/5] Compilazione Clingo Nativo..."
cd ~/clingo-lazy-heuristics/clingo-native
_prep_build_dir build
cd build

cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_AR=/usr/bin/ar \
  -DCMAKE_RANLIB=/usr/bin/ranlib

ninja -j ${SLURM_CPUS_PER_TASK:-2}

echo "==> [5/5] Compilazione Clingo Prolog..."
cd ~/clingo-lazy-heuristics/clingo-prolog
_prep_build_dir build
cd build
cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCLINGO_USE_SWIPL=ON \
  -DCMAKE_PREFIX_PATH=$HOME/swipl-10 \
  -DCMAKE_C_COMPILER=gcc \
  -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_AR=/usr/bin/ar \
  -DCMAKE_RANLIB=/usr/bin/ranlib

ninja -j ${SLURM_CPUS_PER_TASK:-2}

echo "==> COMPILATO CON SUCCESSO"