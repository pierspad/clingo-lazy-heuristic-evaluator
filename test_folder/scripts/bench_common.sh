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

# --- 1) ambiente python: venv + btool + deps grafici ---------
bootstrap_env() {
  cd "$TEST_DIR" || die "cartella test_folder non trovata: $TEST_DIR"

  if [ ! -d .venv ]; then
    log "Creo il virtualenv .venv ..."
    python3 -m venv .venv || die "creazione venv fallita"
  fi
  # shellcheck disable=SC1091
  . .venv/bin/activate || die "attivazione venv fallita"

  local need_pip=0
  command -v btool >/dev/null 2>&1 || need_pip=1
  python3 - <<'PY' >/dev/null 2>&1 || need_pip=1
import importlib
for m in ("pandas", "matplotlib", "openpyxl"):
    importlib.import_module(m)
PY

  if [ "$need_pip" = 1 ]; then
    log "Installo le dipendenze (btool + pandas/matplotlib/openpyxl) ..."
    pip install -q --upgrade pip >/dev/null 2>&1 || true
    pip install -q potassco-benchmark-tool pandas matplotlib openpyxl \
      || die "pip install fallito (controlla la connessione)"
  fi
  command -v btool >/dev/null 2>&1 || die "btool non disponibile dopo l'installazione"
  ok "ambiente python pronto (btool: $(command -v btool))"
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
folders = {"BSP": os.environ["RS_BSP"], "PUP": os.environ["RS_PUP"], "HRP": os.environ["RS_HRP"]}
for b in r.findall("benchmark"):
    f = folders.get(b.get("name"))
    if f:
        for fol in b.findall("folder"):
            fol.set("path", f)
if os.environ.get("RS_DROP_HPC") == "1":
    for p in list(r.findall("project")):
        if p.get("name") == "study-hpc":
            r.remove(p)
    for dj in list(r.findall("distjob")):
        r.remove(dj)
t.write(os.environ["RS_OUT"], encoding="utf-8", xml_declaration=True)
print("scritto", os.environ["RS_OUT"])
PY
}

# --- 5) pipeline btool: gen -> run -> eval -> conv -> plot ---
# uso: run_btool_pipeline <runscript> <output_dir> <project> <machine> \
#                         <results_file> <graphs_dir>
run_btool_pipeline() {
  local rs="$1" out_dir="$2" project="$3" machine="$4" results="$5" graphs="$6"

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

  # 5e) grafici per famiglia/misura
  log "Grafici -> $graphs ..."
  python3 tools/plot_results.py --results "$results" --machine "$machine" \
    --out "$graphs" --measures solving mem decide_calls || die "plot_results.py fallito"
}

# --- 6) riepilogo finale -------------------------------------
summarize() {
  local results="$1" graphs="$2" label="$3"
  echo
  log "RIEPILOGO ($label)"
  if [ -f "$results" ]; then ok "results: $results"; fi
  local n=0
  if [ -d "$graphs" ]; then
    n=$(find "$graphs" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
    ok "grafici PNG generati: $n  (in $graphs/)"
    find "$graphs" -maxdepth 1 -name '*.png' -printf '     - %f\n' 2>/dev/null | sort
  fi
  [ "$n" -gt 0 ] || warn "nessun grafico prodotto: controlla l'output sopra"
}
