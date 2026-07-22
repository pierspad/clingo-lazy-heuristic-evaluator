#!/usr/bin/env bash
# ============================================================
#  GENERAZIONE GRAFICI (SLURM se disponibile, altrimenti in locale)
#  Nome file: 6_plot_graphs_hpc.sh
#
#  tools/plot_results.py espone un registro di job indipendenti
#  (--list-jobs / --only <job_id>): ognuno scrive in una sua sottocartella
#  (nessuna sovrascrittura incrociata). QUESTO stesso script funziona su
#  DUE macchine diverse, senza flag da ricordare:
#    - sull'HPC (sbatch/squeue/sacct in PATH): i job vengono sottomessi come
#      job SLURM separati e spalmati sui nodi liberi di kr/kr-big (v.
#      [[project-hpc-job-granularity]]: erano per lo piu' idle) invece di
#      girare in sequenza su un solo core (~5 minuti);
#    - in locale (nessun sbatch: laptop/desktop, dopo un copyhpcgraphs) i
#      job vengono semplicemente eseguiti uno dopo l'altro nello stesso
#      processo bash, senza SLURM: e' la stessa identita' di job/cartelle,
#      solo senza parallelismo (comunque <1 minuto in pratica).
#  In entrambi i casi l'ultimo job, "summary", DIPENDE dagli altri (copia le
#  PNG gia' prodotte da *:main e comparison): resta fuori dal parallelo e
#  viene eseguito per ultimo, in locale (e' solo I/O, istantaneo).
#
#  Uso (identico sulle due macchine):
#    sh 6_plot_graphs_hpc.sh [--results FILE] [--out-base DIR]
#                             [--ground-counts FILE] [--machine NAME]
#  Senza argomenti usa gli stessi default che 5_evaluate_hpc.sh passava
#  finora a plot_results.py (results.xml in test_folder/benchmark_folder_clingo/,
#  out-base=".." -> test_folder/); infatti 5_evaluate_hpc.sh delega qui la
#  Fase 4 invece di chiamare plot_results.py direttamente. --machine resta
#  "hpc" di default ANCHE quando lo script gira in locale: seleziona quali
#  run dentro results.xml guardare (il tag scritto da chi ha ESEGUITO i
#  benchmark), non la macchina su cui si disegnano i grafici — se copi un
#  results.xml prodotto sul cluster (copyhpcgraphs) e lo ripassi qui in
#  locale, --machine hpc resta corretto.
#
#  Ramo SLURM: lo script sottomette i job e POI FA DA SOLO watch (polling
#  squeue sui soli job che ha appena creato, non su tutta la coda
#  dell'utente) finche' non sono tutti finiti: il prompt torna libero solo
#  a grafici pronti, non serve lanciare wait_hpc.sh a mano ne' rilanciare lo
#  script una seconda volta per il riepilogo.
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
# NB: niente "-e": il loop di poll e la verifica sacct gestiscono gli errori
# a mano e non devono morire su un singolo squeue/sacct fallito a vuoto.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEST_DIR="$REPO_ROOT/test_folder/benchmark_folder_clingo"

# shellcheck disable=SC1091
. "$TEST_DIR/scripts/bench_common.sh"

# ------------------------------------------------------------
#  COSTANTI MODIFICABILI
# ------------------------------------------------------------
PARTITION="kr,kr-big"     # v. [[project-hpc-job-granularity]]: kr-slv escluso, niente association
CPUS_PER_JOB=1            # ogni job disegna PNG con matplotlib: single-core, niente da parallelizzare dentro
MEM_PER_JOB="2G"
TIME_PER_JOB="00:15:00"   # abbondante: un singolo "*:main"/"*:excl:*" impiega di norma <1 minuto
POLL_INTERVAL=10
# ------------------------------------------------------------

RESULTS="$TEST_DIR/results.xml"
OUT_BASE=".."
GROUND_COUNTS=""
MACHINE="hpc"

while [ $# -gt 0 ]; do
  case "$1" in
    --results) RESULTS="$2"; shift 2 ;;
    --out-base) OUT_BASE="$2"; shift 2 ;;
    --ground-counts) GROUND_COUNTS="$2"; shift 2 ;;
    --machine) MACHINE="$2"; shift 2 ;;
    *) die "argomento sconosciuto: $1 (uso: --results FILE --out-base DIR --ground-counts FILE --machine NAME)" ;;
  esac
done

main() {
  log "GENERAZIONE GRAFICI — SLURM se disponibile (partizione '$PARTITION'), altrimenti in locale"

  [ -d "$TEST_DIR" ] || die "cartella non trovata: $TEST_DIR
  Il repo su questa macchina sembra incompleto (push parziale/interrotto?). Verifica con:
    ls -la '$REPO_ROOT'"
  cd "$TEST_DIR" || die "impossibile entrare in $TEST_DIR"

  [ -f "tools/plot_results.py" ] || die "tools/plot_results.py non trovato in: $TEST_DIR/tools/
  Il push su questa macchina non ha portato (o ha portato solo in parte) la cartella tools/.
  Verifica cosa c'e' davvero con:
    ls -la '$TEST_DIR/tools/'
  e ripeti il push del repo (o almeno di test_folder/benchmark_folder_clingo/tools/) prima di rilanciare."

  bootstrap_env
  local VENV_PYTHON="$TEST_DIR/.venv/bin/python3"
  [ -x "$VENV_PYTHON" ] || die "python del venv non trovato/eseguibile: $VENV_PYTHON (bootstrap_env sopra ha fallito?)"

  [ -f "$RESULTS" ] || die "results.xml non trovato: $RESULTS
  Genera prima i risultati (5_evaluate_hpc.sh li produce automaticamente, oppure a mano:
  btool eval runscripts/runscript.xml > results.xml)."

  local gc_arg=()
  [ -n "$GROUND_COUNTS" ] && [ -f "$GROUND_COUNTS" ] && gc_arg=(--ground-counts "$GROUND_COUNTS")

  log "Interrogo tools/plot_results.py per l'elenco dei job indipendenti (--list-jobs) ..."
  mapfile -t JOBS < <("$VENV_PYTHON" tools/plot_results.py \
      --results "$RESULTS" --machine "$MACHINE" --out-base "$OUT_BASE" "${gc_arg[@]}" --list-jobs)
  [ "${#JOBS[@]}" -gt 0 ] || die "--list-jobs non ha restituito nulla (v. eventuale traceback python sopra).
  Controlla a mano: '$VENV_PYTHON' tools/plot_results.py --results '$RESULTS' --list-jobs"

  local PARALLEL_JOBS=() jid
  for jid in "${JOBS[@]}"; do
    [ "$jid" = "summary" ] && continue   # dipende dagli altri: va per ultimo, in locale
    PARALLEL_JOBS+=("$jid")
  done
  log "${#PARALLEL_JOBS[@]} job paralleli da sottomettere (+ 'summary' in locale a fine watch)."

  local MODE
  if command -v sbatch >/dev/null 2>&1 && command -v squeue >/dev/null 2>&1; then
    MODE="HPC parallelo"
    run_jobs_slurm "$VENV_PYTHON" "${PARALLEL_JOBS[@]}"
  else
    MODE="locale sequenziale"
    log "sbatch/squeue non trovati in PATH: niente SLURM qui, eseguo i ${#PARALLEL_JOBS[@]} job in sequenza nel processo corrente."
    run_jobs_local "$VENV_PYTHON" "${PARALLEL_JOBS[@]}"
  fi

  log "Eseguo il job 'summary' in locale (copia le PNG gia' prodotte in riassunto_grafici/) ..."
  "$VENV_PYTHON" tools/plot_results.py --results "$RESULTS" --machine "$MACHINE" \
    --out-base "$OUT_BASE" "${gc_arg[@]}" --only summary

  summarize "$RESULTS" "$OUT_BASE" "$MODE"
}

# ------------------------------------------------------------
#  Ramo HPC: un job SLURM per ogni id, poi watch (poll squeue) + verifica
#  sacct. Identico al comportamento storico dello script.
# ------------------------------------------------------------
run_jobs_slurm() {
  local venv_python="$1"; shift
  local -a parallel_jobs=("$@")

  local LOG_DIR="$TEST_DIR/output/plotlogs"
  mkdir -p "$LOG_DIR"

  local SLURM_IDS=() safe out sid jid
  for jid in "${parallel_jobs[@]}"; do
    safe="$(echo "$jid" | tr ':' '_')"
    out="$(sbatch --job-name="plot-$safe" \
                  --partition="$PARTITION" \
                  --cpus-per-task="$CPUS_PER_JOB" \
                  --mem="$MEM_PER_JOB" \
                  --time="$TIME_PER_JOB" \
                  --output="$LOG_DIR/${safe}-%j.out" \
                  --wrap="cd '$TEST_DIR' && '$venv_python' tools/plot_results.py --results '$RESULTS' --machine '$MACHINE' --out-base '$OUT_BASE' ${gc_arg[*]:-} --only '$jid'")" \
      || die "sbatch fallito per il job '$jid' (output sopra)"
    sid="$(echo "$out" | grep -oE '[0-9]+$')"
    [ -n "$sid" ] || die "non riesco a leggere lo SLURM job id dall'output di sbatch: $out"
    SLURM_IDS+=("$sid")
    log "  -> $jid  (SLURM job $sid, log: $LOG_DIR/${safe}-${sid}.out)"
  done

  ok "${#SLURM_IDS[@]} job sottomessi. Avvio il watch (poll ogni ${POLL_INTERVAL}s, Ctrl-C non li ferma su SLURM) ..."

  # --- watch: poll SOLO sui job appena sottomessi (-j <lista>), non su tutta
  #     la coda dell'utente, per non confonderli con altre campagne in corso
  #     (es. la suite benchmark lanciata da 4_run_benchmark_hpc.sh) ---
  local ids_csv start_ts elapsed n
  ids_csv="$(IFS=,; echo "${SLURM_IDS[*]}")"
  start_ts=$(date +%s)
  while true; do
    n=$(squeue -j "$ids_csv" -h 2>/dev/null | wc -l | tr -d ' ')
    elapsed=$(( $(date +%s) - start_ts ))
    printf "\r[%02d:%02d:%02d] job grafici ancora attivi: %s/%s   " \
      "$((elapsed / 3600))" "$(((elapsed / 60) % 60))" "$((elapsed % 60))" \
      "$n" "${#SLURM_IDS[@]}"
    [ "$n" -eq 0 ] && { echo; break; }
    sleep "$POLL_INTERVAL"
  done

  # --- esito reale: squeue vuoto vuol dire solo "non piu' in coda", non
  #     "riuscito" (stesso avvertimento di wait_hpc.sh) ---
  local failed=0 st
  for sid in "${SLURM_IDS[@]}"; do
    st=$(sacct -j "$sid" -X -n -o State 2>/dev/null | tr -d ' ')
    case "$st" in
      COMPLETED) ;;
      *) warn "job $sid: stato '$st' (log in $LOG_DIR)"; failed=$((failed + 1)) ;;
    esac
  done
  if [ "$failed" -gt 0 ]; then
    warn "$failed/${#SLURM_IDS[@]} job non sono terminati con successo: eseguo comunque 'summary', ma alcune PNG potrebbero mancare o essere quelle di un run precedente."
  else
    ok "Tutti i ${#SLURM_IDS[@]} job sono COMPLETED."
  fi
}

# ------------------------------------------------------------
#  Ramo locale (nessun SLURM in PATH): stessi job, stesso --only, ma
#  eseguiti uno dopo l'altro nel processo corrente. Nessun poll necessario:
#  ogni chiamata a plot_results.py e' gia' sincrona.
# ------------------------------------------------------------
run_jobs_local() {
  local venv_python="$1"; shift
  local -a parallel_jobs=("$@")

  local jid failed=0
  for jid in "${parallel_jobs[@]}"; do
    log "  -> $jid ..."
    if "$venv_python" tools/plot_results.py --results "$RESULTS" --machine "$MACHINE" \
        --out-base "$OUT_BASE" "${gc_arg[@]}" --only "$jid"; then
      :
    else
      warn "job '$jid' terminato con errore (output sopra)"
      failed=$((failed + 1))
    fi
  done
  if [ "$failed" -gt 0 ]; then
    warn "$failed/${#parallel_jobs[@]} job falliti: eseguo comunque 'summary', ma alcune PNG potrebbero mancare o essere quelle di un run precedente."
  else
    ok "Tutti i ${#parallel_jobs[@]} job locali completati."
  fi
}

main
