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

echo "==> [1/5] Caricamento moduli Spack..."
module load cmake/3.31.11-gcc-12.5.0-6sfht6u gcc/12.5.0-gcc-8.3.0-3i7iqwe ninja

echo "==> [2/5] Configurazione e compilazione SWI-Prolog 10..."
cd ~/swipl-moderno/swipl-10.0.2
mkdir -p build && cd build && rm -rf *
export PKG_CONFIG_PATH=$HOME/swipl-10/lib/pkgconfig:${PKG_CONFIG_PATH:-}
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
rm -rf build && mkdir build && cd build

cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_AR=/usr/bin/ar \
  -DCMAKE_RANLIB=/usr/bin/ranlib

ninja -j ${SLURM_CPUS_PER_TASK:-2}

echo "==> [5/5] Compilazione Clingo Prolog..."
cd ~/clingo-lazy-heuristics/clingo-prolog
rm -rf build && mkdir build && cd build
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