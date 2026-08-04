#!/usr/bin/env bash
#SBATCH --partition=kr
#SBATCH --job-name=compile_clingo_swipl
#SBATCH --output=compile_%j.log
#SBATCH --error=compile_%j.log
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
# 45m -> 1h30 (2026-08-03): questo job ora costruisce anche i packages di
# SWI-Prolog (JPL) e il solver Alpha via gradle, che al primo giro si scarica
# la propria distribuzione. Con 4 cpu il vecchio limite era troppo stretto, e
# un job ucciso a meta' lascia una build parziale che poi confonde.
#SBATCH --time=01:30:00

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
  # 1) JAVA_HOME esplicito (sbatch --export=ALL,JAVA_HOME=...)
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/javac" ]; then
    echo "    JDK gia' fornito via JAVA_HOME=$JAVA_HOME"
  else
    # 2) JDK scompattato in $HOME da get_jdk.sh. E' il caso NORMALE su questo
    #    cluster: `module avail` non elenca alcun java (verificato 2026-08-03,
    #    solo toolchain C/C++), quindi il modulo non c'e' proprio da caricare.
    local d
    for d in "$HOME"/jdk-* "$HOME"/jdk; do
      if [ -x "$d/bin/javac" ]; then
        JAVA_HOME="$d"; export JAVA_HOME
        echo "    JDK trovato in \$HOME: $JAVA_HOME"
        break
      fi
    done
  fi
  # 3) modulo (altri cluster, o se un domani ne aggiungono uno qui)
  if [ -z "${JAVA_HOME:-}" ] && command -v module &>/dev/null; then
    local cand
    for cand in openjdk jdk java openjdk/17 openjdk/21; do
      module load "$cand" &>/dev/null && { echo "    modulo java caricato: $cand"; break; }
    done
  fi
  # 4) javac gia' in PATH
  if [ -z "${JAVA_HOME:-}" ] && command -v javac &>/dev/null; then
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
    export JAVA_HOME
  fi
  if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/javac" ]; then
    echo "XX  Nessun JDK trovato (serve javac, non basta il solo java runtime)." >&2
    echo "    Su questo cluster non esiste un modulo java: scaricane uno in \$HOME con" >&2
    echo "      sh get_jdk.sh" >&2
    echo "    e poi rilancia 'sbatch compile_all.sh' (lo trovera' da solo)." >&2
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

# ------------------------------------------------------------
# SELEZIONE DEI PACKAGE: lista ESPLICITA, non i flag di gruppo.
#
# Ci serve un package solo, jpl (jpl.jar + libjpl.so), senza il quale il
# solver Alpha "Qh" — quello con gli aggregati dinamici nelle euristiche,
# che passa da query Prolog — non compila nemmeno. Richiede i sorgenti
# COMPLETI: v. il commento in ../../swipl-moderno/download.sh sul perche'
# l'archive di GitHub non basta.
#
# I flag di gruppo -DSWIPL_PACKAGES_<GRUPPO>=OFF NON bastano, e il modo in
# cui falliscono e' insidioso. cmake/PackageSelection.cmake dichiara
#     set(SWIPL_PKG_DEPS_http clib sgml json ssl)
# e `http` sta nel gruppo BASIC: quindi ssl e json vengono RITIRATI DENTRO
# come dipendenze, e SWIPL_PACKAGES_SSL=OFF resta scritto in CMakeCache
# senza alcun effetto. Sul cluster questo si e' manifestato il 2026-08-03
# come una build morta a 1023/1025 su packages/ssl/tests/test_certs, che
# invoca openssl e non trova openssl.cnf nel prefix Spack. Cioe': falliva
# la generazione di certificati di TEST di un package che non ci serve, e
# si portava dietro l'intero `ninja install` (jpl.jar era gia' stato
# costruito al passo 1022, ma senza install non arriva in $HOME/swipl-10).
#
# SWIPL_PACKAGE_LIST scavalca tutta la macchina dei gruppi: PackageSelection
# la usa se e' gia' DEFINED e salta add_package_sets(). jpl non ha
# dipendenze dichiarate, quindi la lista resta davvero di uno.
#
# Nota: prima del 2026-08-03 qui non si costruiva NESSUN package (i
# submodule erano vuoti) e clingo-prolog funzionava lo stesso, perche' gli
# serve solo libswipl. Costruire il solo jpl e' quindi strettamente piu' di
# quello che c'era, non meno.
# ------------------------------------------------------------
SWIPL_PKGS="jpl"

# Cambiare SWIPL_PACKAGE_LIST su una build dir gia' configurata lascia in
# giro target e cache del vecchio insieme di package. Se la lista non
# combacia, la build dir va ributtata via: e' l'unico caso in cui lo
# facciamo senza CLEAN_BUILD=1, ed e' mirato al solo swipl.
if [ -f CMakeCache.txt ] && ! grep -q "^SWIPL_PACKAGE_LIST:.*=${SWIPL_PKGS}$" CMakeCache.txt; then
  echo "    lista package cambiata: ributto la build dir di SWI-Prolog"
  cd ..; rm -rf build; mkdir -p build; cd build
fi

cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$HOME/swipl-10 \
  -DCMAKE_C_COMPILER=gcc \
  -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_AR=/usr/bin/ar \
  -DCMAKE_RANLIB=/usr/bin/ranlib \
  -DINSTALL_DOCUMENTATION=OFF \
  -DSWIPL_PACKAGE_LIST="$SWIPL_PKGS"

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