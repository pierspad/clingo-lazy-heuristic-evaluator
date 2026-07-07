#!/usr/bin/env bash
# ============================================================
#  VALUTAZIONE E GRAFICI SU CLUSTER (SLURM) - Nome file: 5_evaluate_hpc.sh
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEST_DIR="$REPO_ROOT/test_folder/benchmark_folder_clingo"

# Caricamento delle funzioni core di btool
# shellcheck disable=SC1091
. "$TEST_DIR/scripts/bench_common.sh"

main() {
  log "AVVIO VALUTAZIONE RISULTATI CLUSTER"

  # 1. Verifica se ci sono ancora job attivi in coda su SLURM
  if squeue -u "$USER" 2>/dev/null | grep -q "$USER"; then
    warn "Ci sono ancora job attivi in coda su SLURM!"
    echo "Ti consiglio di attendere che 'squeue -u $USER' sia vuoto prima di estrarre i dati."
    read -p "Vuoi procedere comunque con la valutazione parziale? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      die "Valutazione interrotta dall'utente."
    fi
  fi

  # 2. Attivazione ambiente virtuale per btool e pandas
  cd "$TEST_DIR"
  bootstrap_env

  # Definizione assoluta e rigida degli eseguibili del VENV
  local VENV_PYTHON="$TEST_DIR/.venv/bin/python3"
  local VENV_BTOOL="$TEST_DIR/.venv/bin/btool"
  local VENV_PIP="$TEST_DIR/.venv/bin/pip"

  # 3. Rilevamento dinamico del runscript (Full vs Short_HPC)
  local RUNSCRIPT=""
  local OUTPUT_DIR=""
  
  if [ -f "runscripts/runscript.full.xml" ]; then
    log "Rilevato runscript della SUITE COMPLETA."
    RUNSCRIPT="runscripts/runscript.full.xml"
    OUTPUT_DIR="output"
  elif [ -f "runscripts/runscript.short_hpc.xml" ]; then
    log "Rilevato runscript dello SMOKE TEST."
    RUNSCRIPT="runscripts/runscript.short_hpc.xml"
    OUTPUT_DIR="output-short-hpc"
  else
    die "Nessun runscript valido trovato in 'runscripts/'"
  fi

  # 4. Pulizia dinamica dell'XML temporaneo per forzare btool sul cluster
  log "Fase 1: Ottimizzazione temporanea del runscript per il cluster ..."
  "$VENV_PYTHON" - <<EOF
import xml.etree.ElementTree as ET
tree = ET.parse("$RUNSCRIPT")
root = tree.getroot()
for p in list(root.findall("project")):
    if p.get("name") == "study-local":
        root.remove(p)
tree.write("runscripts/runscript.cluster_tmp.xml", encoding="UTF-8", xml_declaration=True)
EOF

  # 5. Raccolta dati dai log distribuiti usando l'XML ottimizzato
  log "Fase 2: Raccolta log dei job Slurm in results.xml ..."
  "$VENV_BTOOL" eval "runscripts/runscript.cluster_tmp.xml" > results.xml
  rm -f "runscripts/runscript.cluster_tmp.xml"
  ok "File results.xml generato con successo."

  # 6. Conversione in Excel navigabile
  log "Fase 3: Generazione foglio Excel in $OUTPUT_DIR/results.xlsx ..."
  "$VENV_BTOOL" conv -m all -o "$OUTPUT_DIR/results.xlsx" results.xml
  ok "Excel generato con successo."

  # 7. Assicuriamoci che matplotlib sia installato IN QUESTO SPECIFICO VENV prima del plot
  log "Verifica e installazione pacchetti grafici nel venv..."
  "$VENV_PIP" install --quiet matplotlib pandas openpyxl

  # 8. Generazione grafici comparativi pulendo l'ambiente da interferenze
  log "Fase 4: Generazione grafici comparativi (Native vs Prolog) ..."
  PYTHONPATH="" "$VENV_PYTHON" tools/plot_results.py --machine hpc --out-base ..
  
  echo
  ok "ELABORAZIONE COMPLETATA!"
  ok "I dati e l'Excel si trovano in $OUTPUT_DIR/"
  ok "Controlla la directory 'test_folder/' per vedere i grafici generati!"
}

main "$@"