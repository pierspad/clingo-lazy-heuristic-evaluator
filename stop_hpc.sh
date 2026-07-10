#!/usr/bin/env bash
# ============================================================
#  stop_hpc.sh — cancella (in modo pulito) i job SLURM di QUESTO utente.
#
#  SLURM di suo impedisce a "scancel" di toccare job di altri utenti:
#  anche senza filtri, uno scancel lanciato da te puo' colpire solo i
#  TUOI job. Qui in piu': mostriamo la lista PRIMA di cancellare,
#  chiediamo conferma, e aspettiamo che i job spariscano davvero da
#  squeue (non solo che il segnale sia inviato) prima di dichiarare
#  finito — stesso spirito di wait_hpc.sh.
#
#  Uso:
#    sh stop_hpc.sh                 # chiede conferma, cancella TUTTI i
#                                    # job di $USER (incluso l'eventuale
#                                    # wrapper srun di 3_/4_run_benchmark_*.sh)
#    sh stop_hpc.sh -y              # come sopra, senza conferma interattiva
#    sh stop_hpc.sh -b              # solo i job della campagna benchmark
#                                    # (nome "start*", quelli generati da
#                                    # "btool gen" — vedi bench_common.sh)
#    sh stop_hpc.sh -b -y           # combinabili
#    sh stop_hpc.sh -p PATTERN      # filtro nome job custom (regex awk)
#
#  Dopo che questo script conferma "spariti da squeue", puoi rilanciare
#  3_/4_run_benchmark_*.sh senza incappare nel guard ensure_no_pending_dist_jobs
#  (bench_common.sh), che si blocca finche' vede ancora job "start*" in coda.
# ============================================================
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -uo pipefail

POLL_INTERVAL=5
PATTERN=""
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    -b|--benchmark-only) PATTERN='^start' ;;
    -p|--pattern) shift; PATTERN="${1:-}" ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "Opzione sconosciuta: $1 (vedi -h)" >&2; exit 1 ;;
  esac
  shift
done

LIST="$(squeue -u "$USER" -h -o '%i|%j|%T|%M|%N' 2>/dev/null)"
if [ -z "$LIST" ]; then
  echo "==> Nessun job per $USER in coda/esecuzione. Niente da fare."
  exit 0
fi

if [ -n "$PATTERN" ]; then
  LIST="$(printf '%s\n' "$LIST" | awk -F'|' -v pat="$PATTERN" '$2 ~ pat')"
  if [ -z "$LIST" ]; then
    echo "==> Nessun job corrisponde al pattern '$PATTERN'. Niente da fare."
    exit 0
  fi
fi

echo "==> Job che verranno cancellati (solo tuoi, $USER):"
printf '%-12s %-22s %-12s %-10s %s\n' "JOBID" "NAME" "STATE" "TIME" "NODELIST"
printf '%s\n' "$LIST" | awk -F'|' '{printf "%-12s %-22s %-12s %-10s %s\n", $1,$2,$3,$4,$5}'

JOB_IDS=()
while IFS='|' read -r jid _; do
  [ -n "$jid" ] && JOB_IDS+=("$jid")
done <<EOF
$LIST
EOF
N=${#JOB_IDS[@]}

echo
if [ "$ASSUME_YES" != 1 ]; then
  printf "==> Confermi la cancellazione di questi %s job? [s/N] " "$N"
  read -r ans
  case "$ans" in
    s|S|y|Y) ;;
    *) echo "Annullato, nessun job toccato."; exit 0 ;;
  esac
fi

echo "==> Invio scancel a ${N} job ..."
scancel "${JOB_IDS[@]}"
echo "    segnale inviato (SLURM gestisce da solo SIGTERM -> grace period -> SIGKILL)."

echo "==> Attendo la sparizione da squeue per conferma reale (poll ogni ${POLL_INTERVAL}s; Ctrl-C interrompe solo il poll, i job restano in cancellazione) ..."
START_TS=$(date +%s)
while true; do
  STILL="$(squeue -u "$USER" -h -o '%i' 2>/dev/null)"
  REMAINING=0
  for jid in "${JOB_IDS[@]}"; do
    if printf '%s\n' "$STILL" | grep -qx "$jid"; then
      REMAINING=$((REMAINING + 1))
    fi
  done
  ELAPSED=$(( $(date +%s) - START_TS ))
  printf "\r[%02d:%02d] job ancora presenti: %s/%s   " "$((ELAPSED / 60))" "$((ELAPSED % 60))" "$REMAINING" "$N"

  if [ "$REMAINING" -eq 0 ]; then
    echo
    echo "==> Tutti i job richiesti sono spariti da squeue: cancellazione completata."
    break
  fi
  sleep "$POLL_INTERVAL"
done

echo "==> Esito reale (SAT/errore/OOM/cancelled) via: sacct -u \$USER --starttime=today -o JobID,JobName,State,ExitCode"
