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

# ------------------------------------------------------------
# JDK: serve a costruire JPL (jpl.jar + libjpl.so) dentro SWI-Prolog e a
# compilare il solver Alpha. Non c'e' un nome di modulo standard fra i
# cluster, quindi proviamo i candidati piu' comuni e poi verifichiamo che
# javac esista davvero: meglio fallire QUI con un messaggio chiaro che a
# meta' build con un errore di JNI incomprensibile.
# Se il cluster non ha nessun modulo java, basta scompattare un JDK in
# $HOME e lanciare con JAVA_HOME=/percorso/al/jdk sbatch compile_all.sh
# ------------------------------------------------------------
_load_java() {
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/javac" ]; then
    echo "    JDK gia' fornito via JAVA_HOME=$JAVA_HOME"
  elif command -v module &>/dev/null; then
    local cand
    for cand in openjdk jdk java openjdk/17 openjdk/21; do
      module load "$cand" &>/dev/null && { echo "    modulo java caricato: $cand"; break; }
    done
  fi
  if [ -z "${JAVA_HOME:-}" ] && command -v javac &>/dev/null; then
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
    export JAVA_HOME
  fi
  if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/javac" ]; then
    echo "XX  Nessun JDK trovato (serve javac, non basta il solo java runtime)." >&2
    echo "    Prova 'module avail' per cercarne uno, oppure scompatta un JDK in \$HOME e rilancia con:" >&2
    echo "      sbatch --export=ALL,JAVA_HOME=\$HOME/jdk-21 compile_all.sh" >&2
    exit 1
  fi
  export PATH="$JAVA_HOME/bin:$PATH"
  echo "    javac: $(javac -version 2>&1)"
}

echo "==> [1/6] Caricamento moduli Spack..."
module load cmake/3.31.11-gcc-12.5.0-6sfht6u gcc/12.5.0-gcc-8.3.0-3i7iqwe ninja
_load_java

echo "==> [2/6] Configurazione e compilazione SWI-Prolog 10 (con JPL)..."
cd ~/swipl-moderno/swipl-10.0.2
_prep_build_dir build
cd build
export PKG_CONFIG_PATH=$HOME/swipl-10/share/pkgconfig:${PKG_CONFIG_PATH:-}
# SWIPL_PACKAGES_JAVA=ON (era OFF fino al 2026-08-03) e' cio' che produce
# jpl.jar e libjpl.so, senza i quali il solver Alpha "Qh" — quello con gli
# aggregati dinamici nelle euristiche, che passa da query Prolog — non
# compila nemmeno. Richiede i sorgenti COMPLETI: v. il commento in
# ../../swipl-moderno/download.sh sul perche' l'archive di GitHub non basta.
# Tutti gli altri gruppi di package sono spenti esplicitamente: prima non
# se ne costruiva NESSUNO (i submodule erano vuoti), quindi lasciarli ai
# default ora vorrebbe dire allungare la build e aggiungere dipendenze di
# sistema (openssl, libarchive, python, bdb...) che sul cluster possono
# semplicemente non esserci. Teniamo BASIC, che serve a JPL, piu' JAVA.
cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$HOME/swipl-10 \
  -DCMAKE_C_COMPILER=gcc \
  -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_AR=/usr/bin/ar \
  -DCMAKE_RANLIB=/usr/bin/ranlib \
  -DINSTALL_DOCUMENTATION=OFF \
  -DSWIPL_PACKAGES_BASIC=ON -DSWIPL_PACKAGES_JAVA=ON \
  -DSWIPL_PACKAGES_X=OFF -DSWIPL_PACKAGES_ODBC=OFF \
  -DSWIPL_PACKAGES_ARCHIVE=OFF -DSWIPL_PACKAGES_BDB=OFF -DSWIPL_PACKAGES_GUI=OFF \
  -DSWIPL_PACKAGES_JSON=OFF -DSWIPL_PACKAGES_PCRE=OFF -DSWIPL_PACKAGES_PYTHON=OFF \
  -DSWIPL_PACKAGES_SSL=OFF -DSWIPL_PACKAGES_TERM=OFF -DSWIPL_PACKAGES_TIPC=OFF \
  -DSWIPL_PACKAGES_YAML=OFF

ninja -j ${SLURM_CPUS_PER_TASK:-2}
ninja install

# Verifica esplicita: se JPL non e' stato costruito NON si scopre da un
# errore di ninja (il package viene semplicemente saltato), si scopre 20
# minuti dopo quando gradle non trova org.jpl7.
JPL_JAR="$HOME/swipl-10/lib/swipl/lib/jpl.jar"
JPL_LIB_DIR="$HOME/swipl-10/lib/swipl/lib/$(uname -m)-linux"
if [ ! -f "$JPL_JAR" ] || [ ! -f "$JPL_LIB_DIR/libjpl.so" ]; then
  echo "XX  JPL non costruito: manca $JPL_JAR o $JPL_LIB_DIR/libjpl.so" >&2
  echo "    Controlla che ~/swipl-moderno/swipl-10.0.2/packages/jpl NON sia vuota" >&2
  echo "    (rilancia ~/swipl-moderno/download.sh) e che javac sia in PATH." >&2
  exit 1
fi
export JPL_JAR JPL_LIB_DIR
echo "    jpl.jar:   $JPL_JAR"
echo "    libjpl.so: $JPL_LIB_DIR/libjpl.so"

echo "==> [3/6] Esportazione PATH locale per Clingo..."
export PATH=$HOME/swipl-10/bin:$PATH

echo "==> [4/6] Compilazione Clingo Nativo..."
cd ~/clingo-lazy-heuristics/clingo-native
_prep_build_dir build
cd build

cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_AR=/usr/bin/ar \
  -DCMAKE_RANLIB=/usr/bin/ranlib

ninja -j ${SLURM_CPUS_PER_TASK:-2}

echo "==> [5/6] Compilazione Clingo Prolog..."
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

# ------------------------------------------------------------
# Alpha "Qh": il solver lazy-grounding di riferimento, nella variante con
# euristiche domain-specific valutate via query Prolog (flag -uqh). E'
# l'UNICA implementazione esistente degli aggregati dinamici nelle
# euristiche (il paper "Dynamic Aggregates in Expressive ASP Heuristics"):
# il branch upstream domspec_heuristics_extended ha la sintassi ma valuta
# gli aggregati staticamente, quindi non serve a questo confronto.
# Da qui la dipendenza da JPL, e quindi da SWI-Prolog costruito sopra.
#
# La build usa il gradle wrapper, che si scarica la sua distribuzione al
# primo giro: serve rete sul nodo (la stessa che serve gia' al pip install
# di scripts/bench_common.sh).
# ------------------------------------------------------------
echo "==> [6/6] Compilazione Alpha (Qh, euristiche a query Prolog)..."
cd ~/clingo-lazy-heuristics/ALPHA
if [ "$CLEAN_BUILD" = 1 ]; then
  echo "CLEAN_BUILD=1: pulisco ALPHA/build"
  rm -rf build
fi
./gradlew bundledJar --no-daemon -PjplJar="$JPL_JAR"

ALPHA_JAR="$(ls -1 ~/clingo-lazy-heuristics/ALPHA/build/libs/*-bundled.jar 2>/dev/null | head -1)"
[ -n "$ALPHA_JAR" ] || { echo "XX  Alpha: nessun *-bundled.jar in ALPHA/build/libs" >&2; exit 1; }
echo "    alpha jar: $ALPHA_JAR"

echo "==> COMPILATO CON SUCCESSO"