#!/usr/bin/env bash
set -euo pipefail

capture_overrides() {
  local name target
  for name in "$@"; do
    if [ "${!name+x}" ]; then
      target="__OVERRIDE_${name}"
      printf -v "${target}" "%s" "${!name}"
    fi
  done
}

apply_overrides() {
  local name source
  for name in "$@"; do
    source="__OVERRIDE_${name}"
    if [ "${!source+x}" ]; then
      printf -v "${name}" "%s" "${!source}"
    fi
  done
}

LAUNCHER_CONFIG_VARS=(RUN_BSP RUN_PUP ALLOW_LAZY_DEBUG)
capture_overrides "${LAUNCHER_CONFIG_VARS[@]}"

RUN_BSP=true
RUN_PUP=false
ALLOW_LAZY_DEBUG=0

apply_overrides "${LAUNCHER_CONFIG_VARS[@]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BSP_SCRIPT="${SCRIPT_DIR}/1_benchmark_bsp.sh"
PUP_SCRIPT="${SCRIPT_DIR}/3_benchmark_pup.sh"

export RUN_BSP
export RUN_PUP

if [ "${ALLOW_LAZY_DEBUG}" != "1" ]; then
  unset LAZY_HEURISTIC_DEBUG
  unset LAZY_PROLOG_STATS
fi

if [ ! -f "${BSP_SCRIPT}" ]; then
  echo "Errore: script BSP non trovato: ${BSP_SCRIPT}" >&2
  exit 1
fi

START_TIME=$(date +%s)

if [ "${RUN_BSP}" = "true" ]; then
  echo "==============================================================="
  echo " Avvio benchmark BSP"
  echo "==============================================================="
  bash "${BSP_SCRIPT}"
else
  echo "==============================================================="
  echo " Benchmark BSP disabilitato (RUN_BSP!=true)"
  echo "==============================================================="
fi

echo ""
if [ "${RUN_PUP}" = "true" ]; then
  if [ ! -f "${PUP_SCRIPT}" ]; then
    echo "Errore: script PUP non trovato: ${PUP_SCRIPT}" >&2
    exit 1
  fi
  echo "==============================================================="
  echo " Avvio benchmark PUP"
  echo "==============================================================="
  bash "${PUP_SCRIPT}"
else
  echo "==============================================================="
  echo " Benchmark PUP disabilitato (RUN_PUP!=true)"
  echo "==============================================================="
fi

echo ""
END_TIME=$(date +%s)
TOTAL_SECONDS=$((END_TIME - START_TIME))
HOURS=$((TOTAL_SECONDS / 3600))
MINUTES=$(((TOTAL_SECONDS % 3600) / 60))
SECONDS_REMAINING=$((TOTAL_SECONDS % 60))

echo "==============================================================="
echo " Benchmark completato."
printf " Durata totale: %02d ore, %02d minuti, %02d secondi\n" "$HOURS" "$MINUTES" "$SECONDS_REMAINING"
echo " Risultati disponibili in ${TEST_ROOT}/results"
echo "==============================================================="
