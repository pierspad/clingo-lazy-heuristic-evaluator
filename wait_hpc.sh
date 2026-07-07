#!/usr/bin/env bash
# ============================================================
#  wait_hpc.sh — attesa empirica dei job SLURM di questo utente.
#
#  Non da' nessuna garanzia sull'ESITO dei job (potrebbero finire con
#  errore, OOM, timeout): dice solo quando squeue non ne vede piu' in
#  coda/esecuzione, cosa che basta per sapere quando e' il momento di
#  lanciare 5_evaluate_hpc.sh senza incorrere nella race gia' vista
#  (valutare prima che i .dist abbiano finito di scrivere i risultati).
#
#  Uso: sh wait_hpc.sh [intervallo_secondi]
#       (default 30s tra un controllo e l'altro; Ctrl-C per interrompere
#        senza toccare i job, che continuano a girare su SLURM)
# ============================================================
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -uo pipefail

INTERVAL="${1:-10}"
START_TS=$(date +%s)

echo "==> Polling 'squeue -u $USER' ogni ${INTERVAL}s (Ctrl-C per interrompere) ..."

while true; do
  N=$(squeue -u "$USER" -h 2>/dev/null | wc -l | tr -d ' ')
  ELAPSED=$(( $(date +%s) - START_TS ))
  printf "\r[%02d:%02d:%02d] job attivi (pending+running): %s   " \
    "$((ELAPSED / 3600))" "$(((ELAPSED / 60) % 60))" "$((ELAPSED % 60))" "$N"

  if [ "$N" -eq 0 ]; then
    echo
    echo "==> squeue non mostra piu' job per $USER: probabilmente hanno finito."
    echo "    Verifica l'esito reale con 'sacct -u \$USER --starttime=today' prima di fidarti ciecamente,"
    echo "    poi lancia 5_evaluate_hpc.sh."
    break
  fi

  sleep "$INTERVAL"
done
