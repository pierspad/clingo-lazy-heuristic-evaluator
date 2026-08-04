#!/usr/bin/env bash
# ============================================================
# Libreria comune per gli script di benchmark in cartella root:
#   1_run_benchmark_short.sh   (test rapido, timeout breve)
#   2_run_benchmark_full.sh    (suite completa)
#
# NON va eseguita direttamente: viene "source"-ata dagli script entry.
# Tutte le funzioni assumono che $REPO_ROOT e $TEST_DIR siano gia' impostati
# dallo script chiamante, e lavorano con cwd = $TEST_DIR.
#
# Filosofia: ogni passo e' IDEMPOTENTE. Controlla se e' gia' fatto e lo rifa'
# solo se serve (o se forzato con FORCE=1 / REBUILD_CLINGO=1).
# ============================================================

# --- logging -------------------------------------------------
_c_blue="\033[1;34m"; _c_yel="\033[1;33m"; _c_red="\033[1;31m"; _c_grn="\033[1;32m"; _c_off="\033[0m"
log()  { printf "${_c_blue}==>${_c_off} %s\n" "$*"; }
ok()   { printf "${_c_grn} ok${_c_off} %s\n" "$*"; }
warn() { printf "${_c_yel}!! ${_c_off} %s\n" "$*" >&2; }
die()  { printf "${_c_red}XX ${_c_off} %s\n" "$*" >&2; exit 1; }

# --- 0) guard: non ripulire l'output se ci sono ancora job dist attivi ---
# I job generati da "btool gen" hanno nome dello script (start0000.dist,
# troncato da squeue in "start000..."): un run precedente ancora R/PD su
# SLURM puo' avere ancora file aperti in output*/study-hpc*/hpc/results/...
# via NFS. "btool gen -c" fa shutil.rmtree sull'intero output: se ci
# inciampa (silly-rename NFS su un file ancora aperto altrove) muore con
# "Directory not empty" a meta' pulizia, lasciando l'output in uno stato
# ne' vecchio ne' nuovo. Meglio bloccare PRIMA con un messaggio chiaro.
ensure_no_pending_dist_jobs() {
  local running
  running=$(squeue -u "$USER" -h -o "%j" 2>/dev/null | grep -c '^start' || true)
  if [ "${running:-0}" -gt 0 ]; then
    die "Ci sono ancora $running job SLURM (nome 'start*') in coda/esecuzione per \$USER.
  'btool gen -c' ripulisce la cartella di output e puo' scontrarsi con job che ci
  stanno ancora scrivendo dentro (visto in pratica: 'Directory not empty' su un
  run1/ ancora aperto via NFS mentre un job precedente era R su squeue).
  Aspetta la fine con 'sh wait_hpc.sh' (o controlla 'squeue -u \$USER'), poi rilancia."
  fi
}

# --- 1) ambiente python: venv + btool + deps grafici ---------
bootstrap_env() {
  # Carica i moduli completi di Spack identificati sull'HPC
  if command -v module &> /dev/null; then
    log "Caricamento moduli Spack (Python 3.14 + venv)..."
    module load python/3.14.3-gcc-12.5.0-4aiz4ye
    module load python-venv/1.0-none-none-drp2mlh
  fi

  log "Installo le dipendenze (btool + pandas/matplotlib/openpyxl) ..."
  
  # Identifichiamo il binario corretto di Spack caricato dal modulo
  local SPACK_PYTHON
  SPACK_PYTHON=$(command -v python3)

  if [ ! -d ".venv" ]; then
    log "Creazione di un venv pulito usando: $SPACK_PYTHON"
    "$SPACK_PYTHON" -m venv .venv || die "Impossibile creare il venv con Python 3.14"
  fi

  # Attiviamo il venv forzando il PATH pulito
  # shellcheck disable=SC1091
  source .venv/bin/activate

  # Usiamo i binari interni al venv in modo rigido ed esplicito per evitare leak di Python 2.7
  ./.venv/bin/pip install --upgrade pip
  ./.venv/bin/pip install potassco-benchmark-tool pandas matplotlib openpyxl || die "pip install fallito (controlla la connessione)"
}

# --- 2) runlim (limitatore tempo/memoria, binario platform-specific) ---
ensure_runlim() {
  local rl="$TEST_DIR/programs/runlim"
  if [ -x "$rl" ]; then ok "runlim presente"; return 0; fi
  warn "runlim mancante: provo a compilarlo da sorgente ..."
  local tmp; tmp="$(mktemp -d)"
  if git clone --depth 1 https://github.com/arminbiere/runlim "$tmp/runlim" >/dev/null 2>&1 \
     && ( cd "$tmp/runlim" && ./configure.sh >/dev/null 2>&1 && make >/dev/null 2>&1 ) \
     && cp "$tmp/runlim/runlim" "$rl"; then
    chmod +x "$rl"; rm -rf "$tmp"; ok "runlim compilato in programs/runlim"
  else
    rm -rf "$tmp"
    die "Compilazione runlim fallita. Compilalo a mano:
  git clone https://github.com/arminbiere/runlim /tmp/runlim
  cd /tmp/runlim && ./configure.sh && make
  cp runlim $rl"
  fi
}

# --- 3) binari clingo (native + prolog) ----------------------
ensure_clingo_bins() {
  : "${CLINGO_NATIVE_BIN:=$REPO_ROOT/clingo-native/build/bin/clingo}"
  : "${CLINGO_PROLOG_BIN:=$REPO_ROOT/clingo-prolog/build/bin/clingo}"
  export CLINGO_NATIVE_BIN CLINGO_PROLOG_BIN

  local backend bin var
  for backend in native prolog; do
    if [ "$backend" = native ]; then bin="$CLINGO_NATIVE_BIN"; var=CLINGO_NATIVE_BIN
    else bin="$CLINGO_PROLOG_BIN"; var=CLINGO_PROLOG_BIN; fi

    if [ ! -x "$bin" ] || [ "${REBUILD_CLINGO:-0}" = 1 ]; then
      if [ -d "$REPO_ROOT/clingo-$backend/build" ]; then
        log "(Ri)compilo clingo-$backend ..."
        "$TEST_DIR/tools/recompile.sh" "$backend" || warn "recompile clingo-$backend ha segnalato problemi"
      fi
    fi
    [ -x "$bin" ] || die "Binario clingo-$backend mancante: $bin
  Configura/compila la build, oppure esporta $var=/percorso/al/clingo"
  done
  # i wrapper devono essere eseguibili
  chmod +x "$TEST_DIR"/programs/clingo-*-1.0 "$TEST_DIR"/programs/gcat.sh 2>/dev/null || true
  ok "clingo native: $CLINGO_NATIVE_BIN"
  ok "clingo prolog: $CLINGO_PROLOG_BIN"
}

# --- 3bis) jar di Alpha (Qh) --------------------------------
# Alpha e' il sistema di riferimento esterno del confronto (v. il <system>
# alpha-qh in runscripts/runscript.xml). Il jar NON viene ricompilato qui:
# la sua build dipende da JPL, e quindi da SWI-Prolog costruito con
# -DSWIPL_PACKAGES_JAVA=ON, che e' compito di compile_all.sh. Qui si
# verifica soltanto che ci sia, e si fallisce SUBITO se manca.
#
# Il perche' del "fallisci subito": un jar assente non e' un errore che
# btool sappia riconoscere. I run di alpha-qh fallirebbero uno per uno, la
# campagna arriverebbe in fondo, i grafici verrebbero disegnati, e Alpha
# comparirebbe come una riga di timeout al 100% - indistinguibile da un
# risultato vero. Esattamente lo stesso genere di fallimento silenzioso
# contro cui esiste il flag lazy_active per il backend prolog.
ensure_alpha_jar() {
  : "${ALPHA_JAR:=$(ls -1 "$REPO_ROOT"/ALPHA/build/libs/*-bundled.jar 2>/dev/null | head -1)}"
  : "${SWIPL_MODERN_PREFIX:=$HOME/swipl-10}"
  # -Xmx deve stare SOTTO il memout di runlim: se la JVM puo' riservare piu'
  # RAM del limite, il run muore di OOM-kill di sistema invece che di memout
  # pulito, e il resultparser non ha modo di distinguerlo da un crash.
  # Il chiamante puo' sovrascriverlo (la suite short gira con memout molto
  # piu' basso).
  : "${ALPHA_XMX:=28g}"
  export ALPHA_JAR SWIPL_MODERN_PREFIX ALPHA_XMX

  if [ -z "$ALPHA_JAR" ] || [ ! -f "$ALPHA_JAR" ]; then
    die "Jar di Alpha mancante (atteso in $REPO_ROOT/ALPHA/build/libs/*-bundled.jar).
  Lancialo con 'sbatch compile_all.sh' (passo [6/6]), oppure esporta ALPHA_JAR=/percorso/al/jar.
  Se compile_all.sh fallisce sul passo Alpha, quasi sempre e' JPL: controlla che
  ~/swipl-moderno/swipl-10.0.2/packages/jpl NON sia vuota (rilancia download.sh)."
  fi

  local jpl="$SWIPL_MODERN_PREFIX/lib/swipl/lib/jpl.jar"
  local libjpl="$SWIPL_MODERN_PREFIX/lib/swipl/lib/$(uname -m)-linux/libjpl.so"
  [ -f "$libjpl" ] || die "libjpl.so mancante: $libjpl
  Alpha compila anche senza, ma a runtime muore con UnsatisfiedLinkError.
  Ricostruisci SWI-Prolog con -DSWIPL_PACKAGES_JAVA=ON (compile_all.sh)."
  [ -f "$jpl" ] || warn "jpl.jar non trovato in $jpl (serve solo alla build, non al run)"

  chmod +x "$TEST_DIR"/programs/alpha-qh-1.0 2>/dev/null || true

  # --- smoke run: 2 secondi che valgono tre controlli statici -------------
  # Un programma banale con -uqh esercita l'INTERA catena: jar presente,
  # JVM abbastanza recente, libjpl.so caricabile, motore Prolog avviato
  # (NaiveGrounder istanzia il modulo Prolog anche senza euristiche).
  # Serve perche' i modi di rompersi qui sono tutti silenziosi o tardivi:
  #   - JVM piu' vecchia del JDK che ha costruito jpl.jar -> a runtime
  #     UnsupportedClassVersionError (successo il 2026-08-03: java 11 di
  #     sistema sul login node contro jpl.jar compilato con il JDK 21 di
  #     get_jdk.sh). Il wrapper ora sceglie la JVM da se', ma se qualcuno
  #     forza ALPHA_JAVA a mano si torna li';
  #   - libjpl.so assente -> UnsatisfiedLinkError, messaggio che non
  #     assomiglia per niente a "manca SWI-Prolog".
  # Senza questo guard il sintomo arriva a campagna avviata, run per run,
  # sotto forma di centinaia di errori identici.
  local probe
  if ! probe=$("$TEST_DIR/programs/alpha-qh-1.0" -uqh -n 1 -str "p(1). q(X) :- p(X)." 2>&1); then
    die "Alpha non parte. Output:
$(echo "$probe" | tail -15)"
  fi
  case "$probe" in
    *SATISFIABLE*) ok "alpha jar: $ALPHA_JAR (heap max $ALPHA_XMX)" ;;
    *) die "Alpha parte ma non risolve il programma di prova. Output:
$(echo "$probe" | tail -15)" ;;
  esac
}

# --- 4) deriva un runscript dal canonico --------------------
# uso: derive_runscript <in.xml> <out.xml> <timeout_sec> <output_attr> \
#                       <bsp_folder> <pup_folder> <hrp_folder> <drop_hpc:0|1>
derive_runscript() {
  RS_IN="$1" RS_OUT="$2" RS_TIMEOUT="${3}s" RS_OUTPUT="$4" \
  RS_BSP="$5" RS_PUP="$6" RS_HRP="$7" RS_DROP_HPC="$8" \
  python3 - <<'PY' || die "derivazione runscript fallita"
import os, xml.etree.ElementTree as ET
t = ET.parse(os.environ["RS_IN"]); r = t.getroot()
r.set("output", os.environ["RS_OUTPUT"])
for sj in r.findall("seqjob"):
    sj.set("timeout", os.environ["RS_TIMEOUT"])
for dj in r.findall("distjob"):
    dj.set("timeout", os.environ["RS_TIMEOUT"])
folders = {"BSP": os.environ["RS_BSP"], "PUP": os.environ["RS_PUP"], "HRP": os.environ["RS_HRP"]}
for b in r.findall("benchmark"):
    f = folders.get(b.get("name"))
    if f:
        for fol in b.findall("folder"):
            fol.set("path", f)
if os.environ.get("RS_DROP_HPC") == "1":
    # prefix match: dopo lo split di study-hpc in study-hpc-{bsp,pup,hrp}
    # (vedi runscript.xml) un confronto per uguaglianza esatta lascerebbe
    # questi project orfani con job="dist-hpc" gia' rimosso sotto.
    for p in list(r.findall("project")):
        if p.get("name", "").startswith("study-hpc"):
            r.remove(p)
    for dj in list(r.findall("distjob")):
        r.remove(dj)
t.write(os.environ["RS_OUT"], encoding="utf-8", xml_declaration=True)
print("scritto", os.environ["RS_OUT"])
PY
}

# --- 5) pipeline btool: gen -> run -> eval -> conv -> plot ---
# uso: run_btool_pipeline <runscript> <output_dir> <project> <machine> \
#                         <results_file> <out_base>
# <out_base> = cartella che conterra' i tre alberi di grafici
#   graphs-native/, graphs-prolog/, graphs-comparison-native-prolog/.
#   ".." per la full (-> test_folder), "." per la short (-> resta qui).
run_btool_pipeline() {
  local rs="$1" out_dir="$2" project="$3" machine="$4" results="$5" out_base="$6"

  # 5a) genera gli script di run.
  #     FORCE=1 -> pulisce e rigenera tutto (rerun completo)
  #     altrimenti -> update (tiene i run gia' .finished) o prima generazione
  if [ "${FORCE:-0}" = 1 ]; then
    log "btool gen -c (rerun forzato, pulisco $out_dir) ..."
    btool gen -c "$rs" || die "btool gen fallito"
  elif [ -d "$out_dir/$project" ]; then
    log "btool gen -u (aggiorno, tengo i run gia' completati) ..."
    btool gen -u "$rs" || die "btool gen fallito"
  else
    log "btool gen (prima generazione) ..."
    btool gen "$rs" || die "btool gen fallito"
  fi

  # 5b) esegui sequenzialmente. start.py fa chdir da se': passare il percorso.
  local start="$out_dir/$project/$machine/start.py"
  [ -f "$start" ] || die "start.py non generato: $start"
  log "Eseguo i run ($project) — start.py salta quelli gia' .finished ..."
  python3 "$start" || die "esecuzione run fallita"

  # 5c) raccogli i risultati
  log "btool eval -> $results ..."
  btool eval "$rs" > "$results" || die "btool eval fallito"

  # 5d) foglio xlsx navigabile (non bloccante)
  if btool conv -m all -o "$out_dir/results.xlsx" "$results" >/dev/null 2>&1; then
    ok "xlsx: $out_dir/results.xlsx"
  else
    warn "btool conv (xlsx) fallito — proseguo coi grafici"
  fi

  # 5e) grafici: tre alberi (native / prolog / confronto) sotto out_base.
  #     ground_counts.csv (se presente) abilita i grafici di grounding.
  log "Grafici -> $out_base/{graphs-native,graphs-prolog,graphs-comparison-native-prolog,graphs-comparison-clingo-alpha}/ ..."
  local gc_arg=()
  [ -f "$out_dir/ground_counts.csv" ] && gc_arg=(--ground-counts "$out_dir/ground_counts.csv")
  python3 tools/plot_results.py --results "$results" --machine "$machine" \
    --out-base "$out_base" "${gc_arg[@]}" || die "plot_results.py fallito"
}

# --- 6) riepilogo finale -------------------------------------
summarize() {
  local results="$1" out_base="$2" label="$3"
  echo
  log "RIEPILOGO ($label)"
  if [ -f "$results" ]; then ok "results: $results"; fi
  local n=0 tree
  for tree in graphs-native graphs-prolog graphs-comparison-native-prolog graphs-comparison-clingo-alpha; do
    if [ -d "$out_base/$tree" ]; then
      local c
      c=$(find "$out_base/$tree" -name '*.png' | wc -l | tr -d ' ')
      ok "$tree/: $c PNG"
      n=$((n + c))
    fi
  done
  [ "$n" -gt 0 ] || warn "nessun grafico prodotto: controlla l'output sopra"
}
