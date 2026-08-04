#!/usr/bin/env bash
# ============================================================
#  JDK PORTABILE IN $HOME - Nome file: get_jdk.sh
#
#  PERCHE' ESISTE
#  compile_all.sh ha bisogno di un JDK (javac, non solo il runtime java) per
#  due cose: costruire JPL dentro SWI-Prolog (jpl.jar + libjpl.so) e compilare
#  il solver Alpha. Sul cluster kr NON c'e' alcun modulo java: `module avail`
#  elenca solo toolchain C/C++ (gcc, cmake, ninja, binutils, ...), verificato
#  il 2026-08-03. Senza modulo, l'unica strada e' un JDK scompattato in $HOME.
#
#  COSA FA
#  Scarica Eclipse Temurin (build ufficiale di OpenJDK), verifica lo sha256 e
#  lo scompatta in $HOME/jdk-21. Da li' compile_all.sh lo trova da solo: cerca
#  $HOME/jdk-* prima di arrendersi.
#
#  Nessun privilegio di root, nessun package manager: e' solo un tar.gz.
#
#  VERSIONE PINNATA, non "latest": una campagna di benchmark dev'essere
#  ripetibile, e un JDK che cambia sotto i piedi fra due run e' esattamente il
#  genere di variabile silenziosa che non si vuole. Lo sha256 serve all'altro
#  problema tipico dei cluster, il download troncato: senza verifica, un tar.gz
#  a meta' si manifesta molto piu' tardi come un errore di compilazione
#  incomprensibile.
#
#  Temurin 21 e' compilato contro glibc 2.17; il cluster e' Debian 10
#  (glibc 2.28), quindi gira.
#
#  Per aggiornare versione: cambia JDK_VERSION/JDK_BUILD/JDK_SHA256 qui sotto.
#  I valori si prendono da:
#    curl -s 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse'
#
#  Uso:
#    sh get_jdk.sh            # scarica se manca
#    FORCE=1 sh get_jdk.sh    # riscarica anche se c'e' gia'
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

# ------------------------------------------------------------
#  COSTANTI MODIFICABILI
# ------------------------------------------------------------
JDK_VERSION="21.0.12"
JDK_BUILD="8"
JDK_SHA256="e4446ff06a276155697597cc0f1b15da004ff083f4964a35271ecee567177370"
JDK_PREFIX="${JDK_PREFIX:-$HOME/jdk-21}"
# ------------------------------------------------------------

_c_blue="\033[1;34m"; _c_yel="\033[1;33m"; _c_red="\033[1;31m"; _c_grn="\033[1;32m"; _c_off="\033[0m"
log()  { printf "${_c_blue}==>${_c_off} %s\n" "$*"; }
ok()   { printf "${_c_grn} ok${_c_off} %s\n" "$*"; }
warn() { printf "${_c_yel}!! ${_c_off} %s\n" "$*" >&2; }
die()  { printf "${_c_red}XX ${_c_off} %s\n" "$*" >&2; exit 1; }

TARBALL="OpenJDK21U-jdk_x64_linux_hotspot_${JDK_VERSION}_${JDK_BUILD}.tar.gz"
URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${JDK_VERSION}%2B${JDK_BUILD}/${TARBALL}"

if [ -x "$JDK_PREFIX/bin/javac" ] && [ "${FORCE:-0}" != 1 ]; then
  ok "JDK gia' presente: $JDK_PREFIX"
  "$JDK_PREFIX/bin/javac" -version
  echo
  log "Per usarlo:  export JAVA_HOME=$JDK_PREFIX"
  exit 0
fi

command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
  || die "servono curl o wget per scaricare il JDK"
command -v sha256sum >/dev/null 2>&1 || die "serve sha256sum per verificare il download"

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

log "Scarico Temurin JDK ${JDK_VERSION}+${JDK_BUILD} (~208 MB) ..."
log "  $URL"
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 --retry-delay 5 -o "$tmp/$TARBALL" "$URL" \
    || die "download fallito. Il nodo di login ha rete? (la stessa che serve al pip install di bench_common.sh)"
else
  wget -q --tries=3 -O "$tmp/$TARBALL" "$URL" || die "download fallito (wget)"
fi

log "Verifico lo sha256 ..."
echo "${JDK_SHA256}  $tmp/$TARBALL" | sha256sum -c - >/dev/null 2>&1 \
  || die "sha256 NON corrispondente: download corrotto/troncato, oppure la release e' cambiata.
  Atteso:  $JDK_SHA256
  Ottenuto: $(sha256sum "$tmp/$TARBALL" | cut -d' ' -f1)
  Se hai cambiato JDK_VERSION, aggiorna anche JDK_SHA256 (v. header)."
ok "checksum verificato"

log "Scompatto in $JDK_PREFIX ..."
rm -rf "$JDK_PREFIX"
mkdir -p "$JDK_PREFIX"
# --strip-components=1: il tarball contiene una cartella jdk-21.0.12+8/, ma
# noi vogliamo bin/ e lib/ direttamente sotto $JDK_PREFIX, cosi' il path non
# dipende dal numero di build e compile_all.sh non deve indovinarlo.
tar -xzf "$tmp/$TARBALL" -C "$JDK_PREFIX" --strip-components=1

[ -x "$JDK_PREFIX/bin/javac" ] || die "javac non trovato dopo l'estrazione: $JDK_PREFIX/bin/javac"

echo
ok "JDK installato in $JDK_PREFIX"
"$JDK_PREFIX/bin/javac" -version
"$JDK_PREFIX/bin/java" -version
echo
log "compile_all.sh lo trovera' da solo (cerca \$HOME/jdk-*). Prossimo passo:"
log "  sbatch compile_all.sh"
