#!/usr/bin/env bash
# ============================================================
# PINNING DEI JOB DI MISURA SU UN INSIEME OMOGENEO DI NODI SLURM
#
# PERCHE' ESISTE QUESTO FILE
#   Fino al 2026-08-14 il <distjob> dichiarava partition="kr,kr-big" e SLURM
#   dispacciava ogni allocazione sul primo nodo libero delle due partizioni.
#   I nodi NON sono identici, e l'effetto e' misurabile: tre varianti BSP che
#   groundano lo stesso identico programma (gc_noheur, la, lc — 52.759.256
#   regole contro 52.759.258) mostrano tempi di grounding che divergono del
#   28% mediano e fino al 46% a n=140. Al top del range BSP quello scarto e'
#   abbastanza grande da decidere da che parte del limite di 600s cade un run,
#   cioe' da spostare la frontiera di una variante per motivi che non hanno
#   niente a che vedere con la variante. Il capitolo Risultati ha dovuto
#   dichiararlo come caveat (\label{sec:node-variance}) e rinunciare a ogni
#   claim basato sul tempo tra varianti same-encoding.
#   `--exclusive` era gia' nel template (nessun altro job condivide la RAM),
#   quindi la varianza residua e' hardware, non contesa: si toglie scegliendo
#   i nodi.
#
# PERCHE' NON UN NODO SOLO
#   Un singolo nodo azzera la varianza ma serializza la campagna: i job sono
#   `--exclusive`, quindi su un nodo ne gira uno per volta. I ~50 *.dist
#   generati da "btool gen" passerebbero da ~12 allocazioni concorrenti a 1.
#   Pinnare su un GRUPPO OMOGENEO (stessa CPU, stessi socket/core/thread,
#   stessa RAM) da' lo stesso risultato metrologico mantenendo il parallelismo.
#
# COME
#   La partizione di default scende da "kr,kr-big" a "kr" e, DENTRO quella
#   partizione, i nodi che non appartengono al gruppo omogeneo piu' numeroso
#   vengono esclusi con `--exclude`. Si usa `--exclude` e non `--nodelist`
#   perche' `--nodelist` in sbatch e' una richiesta di avere TUTTI quei nodi
#   nell'allocazione, non "scegline uno tra questi": con `-N 1` implicito il
#   comportamento e' ambiguo, mentre `--exclude` significa esattamente
#   "allocami dove vuoi tranne qui".
#
#   La scelta viene fatta UNA VOLTA e congelata in $HPC_TARGET_LOCK
#   (.hpc_target.conf nella root del repo, generato sull'HPC, non tracciato).
#   Congelarla non e' un dettaglio: se il gruppo venisse ricalcolato a ogni
#   sottomissione, un nodo entrato in DRAIN a meta' campagna cambierebbe
#   l'insieme e i run prima/dopo tornerebbero a non essere confrontabili —
#   cioe' si riaprirebbe esattamente il problema che questo file chiude.
#   Per ricalcolarlo di proposito: HPC_TARGET_REFRESH=1, o cancella il lock.
#
# CONFIGURAZIONE (tutte sovrascrivibili da env)
#   HPC_PARTITION       partizione SLURM (default: kr)
#   HPC_NODES           AUTO  -> rileva il gruppo omogeneo piu' numeroso
#                       ALL   -> nessuna restrizione (comportamento vecchio)
#                       <hostlist> -> insieme esplicito, es. "kr[01-06]"
#                                     o un nodo solo, es. "kr07"
#   HPC_TARGET_REFRESH  1 -> ignora il lock e ricalcola
#   HPC_TARGET_LOCK     percorso del lock (default: <repo>/.hpc_target.conf)
#
# USO
#   . scripts/hpc_target.sh
#   hpc_target_ensure          # risolve (o carica) il target
#   hpc_pin_args               # popola l'array HPC_PIN_ARGS per srun/sbatch
#   srun "${HPC_PIN_ARGS[@]}" ...
#
#   Eseguito direttamente (non sourcato) stampa l'inventario dei nodi della
#   partizione e il target risolto — utile per documentare in tesi su che
#   hardware ha girato la campagna:
#       bash scripts/hpc_target.sh
# ============================================================

# --- include guard: questo file viene sourcato sia dai guard srun di
#     3_/4_run_benchmark_*.sh (prima di bench_common.sh) sia da
#     bench_common.sh stesso. Senza guard il secondo source azzererebbe
#     HPC_TARGET_* lasciando pero' _HPC_TARGET_READY impostato, cioe' un
#     target "risolto" e vuoto: nessun pinning, in silenzio.
if [ -n "${_HPC_TARGET_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi
_HPC_TARGET_SOURCED=1

# --- fallback di logging: questo file puo' essere sourcato PRIMA di
#     bench_common.sh (i guard srun di 3_/4_ lo fanno), quindi non puo'
#     dare per scontate log/warn/ok/die. Se bench_common.sh viene sourcato
#     dopo, ridefinisce le stesse funzioni con la versione colorata.
if ! declare -F log  >/dev/null 2>&1; then log()  { printf '==> %s\n'  "$*"; }; fi
if ! declare -F warn >/dev/null 2>&1; then warn() { printf '!!  %s\n'  "$*" >&2; }; fi
if ! declare -F ok   >/dev/null 2>&1; then ok()   { printf ' ok %s\n'  "$*"; }; fi
if ! declare -F die  >/dev/null 2>&1; then die()  { printf 'XX  %s\n'  "$*" >&2; exit 1; }; fi

: "${HPC_PARTITION:=kr}"
: "${HPC_NODES:=AUTO}"
: "${HPC_TARGET_REFRESH:=0}"

# root del repo dedotta dalla posizione di QUESTO file
# (<repo>/test_folder/benchmark_folder_clingo/scripts/hpc_target.sh)
_HPC_SELF="${BASH_SOURCE[0]:-$0}"
_HPC_REPO_ROOT="$(cd "$(dirname "$_HPC_SELF")/../../.." && pwd)"
: "${HPC_TARGET_LOCK:=$_HPC_REPO_ROOT/.hpc_target.conf}"

# Valorizzati da hpc_target_ensure():
HPC_TARGET_NODES=""     # hostlist dei nodi ammessi ("" = nessuna restrizione)
HPC_TARGET_EXCLUDE=""   # hostlist dei nodi esclusi ("" = niente --exclude)
HPC_TARGET_SIG=""       # firma hardware del gruppo scelto (per il record)

_hpc_have_slurm() { command -v scontrol >/dev/null 2>&1; }

# Comprime "a1,a2,a3" in "a[1-3]". E' solo leggibilita' — sbatch accetta
# benissimo la lista con le virgole — ma il valore compresso finisce in una
# riga "#SBATCH ..exclude=" e in un lock che si legge a mesi di distanza,
# quindi conviene che sia leggibile.
#
# La compressione viene RIVERIFICATA: si riespande e si confronta con
# l'insieme di partenza, e al minimo disaccordo si tiene la lista originale.
# Non e' paranoia gratuita: un insieme sbagliato qui non da' nessun errore
# visibile, da' una campagna che gira sui nodi sbagliati (o job che restano
# in PD per sempre perche' abbiamo escluso anche i nostri). Il costo del
# controllo e' una chiamata a scontrol; il costo di sbagliare e' rifare tutto.
_hpc_compress() {
  local list="$1" packed back
  [ -n "$list" ] || { echo ""; return 0; }
  command -v scontrol >/dev/null 2>&1 || { echo "$list"; return 0; }

  packed="$(scontrol show hostlistsorted "$list" 2>/dev/null)" || { echo "$list"; return 0; }
  [ -n "$packed" ] || { echo "$list"; return 0; }

  back="$(scontrol show hostnames "$packed" 2>/dev/null | sort | paste -sd, -)"
  if [ "$back" = "$(printf '%s' "$list" | tr ',' '\n' | sort | paste -sd, -)" ]; then
    echo "$packed"
  else
    warn "compressione hostlist non fedele ('$list' -> '$packed'): uso la lista estesa."
    echo "$list"
  fi
}

# espande "kr[01-06]" in "kr01,kr02,..."
_hpc_expand() {
  local list="$1"
  [ -n "$list" ] || { echo ""; return 0; }
  if command -v scontrol >/dev/null 2>&1; then
    scontrol show hostnames "$list" 2>/dev/null | paste -sd, - || echo "$list"
  else
    echo "$list"
  fi
}

# tutti i nodi della partizione, uno per riga, con la loro firma hardware:
#   <nodo> <TAB> <CPUTot|RealMemory|Sockets|CoresPerSocket|ThreadsPerCore|Features>
# Si legge da `scontrol show node --oneliner` e non da `sinfo -o`: sinfo
# incolonna i campi con padding a larghezza fissa, scontrol no.
_hpc_node_table() {
  scontrol show node --oneliner 2>/dev/null | awk -v want="$HPC_PARTITION" '
    {
      name=""; cpus=""; mem=""; sock=""; core=""; thr=""; feat=""; parts="";
      n = split($0, f, " ");
      for (i = 1; i <= n; i++) {
        p = index(f[i], "=");
        if (p == 0) continue;
        k = substr(f[i], 1, p - 1);
        v = substr(f[i], p + 1);
        if      (k == "NodeName")       name = v;
        else if (k == "CPUTot")         cpus = v;
        else if (k == "RealMemory")     mem  = v;
        else if (k == "Sockets")        sock = v;
        else if (k == "CoresPerSocket") core = v;
        else if (k == "ThreadsPerCore") thr  = v;
        else if (k == "AvailableFeatures") feat = v;
        else if (k == "Partitions")     parts = v;
      }
      if (name == "" || parts == "") next;
      hit = 0;
      m = split(parts, pl, ",");
      for (i = 1; i <= m; i++) if (pl[i] == want) hit = 1;
      if (!hit) next;
      printf "%s\t%s|%s|%s|%s|%s|%s\n", name, cpus, mem, sock, core, thr, feat;
    }'
}

# gruppo omogeneo piu' numeroso: stampa "<firma>\t<nodi,virgola>\t<quanti>"
# A parita' di numerosita' vince la firma con piu' core (nodi piu' grossi), e
# a parita' di quella l'ordine lessicografico — deterministico, cosi' due
# risoluzioni sullo stesso cluster danno lo stesso insieme.
_hpc_largest_group() {
  _hpc_node_table | awk -F'\t' '
    { cnt[$2]++; nodes[$2] = (nodes[$2] == "" ? $1 : nodes[$2] "," $1) }
    END {
      best = 0; bestsig = ""; bestcores = -1;
      for (s in cnt) {
        split(s, p, "|");
        cores = p[1] + 0;
        if (cnt[s] > best ||
            (cnt[s] == best && cores > bestcores) ||
            (cnt[s] == best && cores == bestcores && s < bestsig)) {
          best = cnt[s]; bestsig = s; bestcores = cores;
        }
      }
      if (best > 0) printf "%s\t%s\t%d\n", bestsig, nodes[bestsig], best;
    }'
}

_hpc_write_lock() {
  {
    echo "# Insieme di nodi congelato per la campagna di misura."
    echo "# Generato da scripts/hpc_target.sh il $(date -Is) su $(hostname)."
    echo "# Cancella questo file (o esporta HPC_TARGET_REFRESH=1) per ricalcolarlo;"
    echo "# ricalcolarlo a meta' campagna rende i run prima/dopo non confrontabili."
    echo "HPC_PARTITION=$HPC_PARTITION"
    echo "HPC_TARGET_NODES=$HPC_TARGET_NODES"
    echo "HPC_TARGET_EXCLUDE=$HPC_TARGET_EXCLUDE"
    echo "HPC_TARGET_SIG=\"$HPC_TARGET_SIG\""
  } > "$HPC_TARGET_LOCK"
}

_hpc_read_lock() {
  [ -f "$HPC_TARGET_LOCK" ] || return 1
  # shellcheck disable=SC1090
  . "$HPC_TARGET_LOCK" || return 1
  [ -n "${HPC_TARGET_NODES:-}" ] || [ -n "${HPC_TARGET_EXCLUDE:-}" ]
}

# Calcola l'esclusione a partire dall'insieme ammesso: tutti i nodi della
# partizione che non ci stanno dentro.
_hpc_exclude_from_nodes() {
  local allowed_expanded="$1" all node
  all="$(_hpc_node_table | cut -f1)"
  local excl=""
  for node in $all; do
    case ",$allowed_expanded," in
      *",$node,"*) ;;
      *) excl="${excl:+$excl,}$node" ;;
    esac
  done
  echo "$excl"
}

# --- API principale ------------------------------------------
# Risolve il target una volta per processo. Idempotente.
hpc_target_ensure() {
  [ -n "${_HPC_TARGET_READY:-}" ] && return 0
  _HPC_TARGET_READY=1

  if ! _hpc_have_slurm; then
    # in locale (laptop, 6_plot_graphs_hpc.sh senza SLURM) non c'e' niente da
    # pinnare: tutte le funzioni diventano no-op
    HPC_TARGET_NODES=""; HPC_TARGET_EXCLUDE=""; HPC_TARGET_SIG=""
    return 0
  fi

  if [ "$HPC_NODES" = "ALL" ]; then
    warn "HPC_NODES=ALL: nessun pinning, i job vanno su qualunque nodo di '$HPC_PARTITION'.
  I tempi tornano a portarsi dietro la varianza inter-nodo (v. sec:node-variance)."
    HPC_TARGET_NODES=""; HPC_TARGET_EXCLUDE=""; HPC_TARGET_SIG="(nessun pinning)"
    return 0
  fi

  if [ "$HPC_NODES" != "AUTO" ]; then
    # insieme esplicito imposto dall'utente: niente lock, comanda l'env
    local expanded
    expanded="$(_hpc_expand "$HPC_NODES")"
    HPC_TARGET_NODES="$(_hpc_compress "$expanded")"
    HPC_TARGET_EXCLUDE="$(_hpc_compress "$(_hpc_exclude_from_nodes "$expanded")")"
    HPC_TARGET_SIG="(imposto a mano via HPC_NODES)"
    ok "Nodi di misura (espliciti): $HPC_TARGET_NODES su partizione '$HPC_PARTITION'"
    return 0
  fi

  if [ "$HPC_TARGET_REFRESH" != "1" ] && _hpc_read_lock; then
    ok "Nodi di misura (dal lock $HPC_TARGET_LOCK): ${HPC_TARGET_NODES:-tutti} su partizione '$HPC_PARTITION'"
    [ -n "$HPC_TARGET_EXCLUDE" ] && log "    esclusi: $HPC_TARGET_EXCLUDE"
    return 0
  fi

  local row sig nodes count
  row="$(_hpc_largest_group)"
  if [ -z "$row" ]; then
    warn "Non riesco a leggere i nodi della partizione '$HPC_PARTITION' (scontrol show node).
  Proseguo SENZA pinning: i tempi manterranno la varianza inter-nodo."
    HPC_TARGET_NODES=""; HPC_TARGET_EXCLUDE=""; HPC_TARGET_SIG="(rilevamento fallito)"
    return 0
  fi
  sig="$(printf '%s' "$row" | cut -f1)"
  nodes="$(printf '%s' "$row" | cut -f2)"
  count="$(printf '%s' "$row" | cut -f3)"

  HPC_TARGET_NODES="$(_hpc_compress "$nodes")"
  HPC_TARGET_EXCLUDE="$(_hpc_compress "$(_hpc_exclude_from_nodes "$nodes")")"
  HPC_TARGET_SIG="$sig"
  _hpc_write_lock

  ok "Gruppo omogeneo scelto in '$HPC_PARTITION': $count nodi -> $HPC_TARGET_NODES"
  log "    firma hw (CPUTot|RealMemory|Sockets|CoresPerSocket|ThreadsPerCore|Features): $sig"
  if [ -n "$HPC_TARGET_EXCLUDE" ]; then
    log "    esclusi (hardware diverso): $HPC_TARGET_EXCLUDE"
  else
    log "    nessun nodo escluso: la partizione e' gia' omogenea"
  fi
  log "    scelta congelata in $HPC_TARGET_LOCK"
}

# Popola l'array HPC_PIN_ARGS con gli argomenti da passare a srun/sbatch.
hpc_pin_args() {
  hpc_target_ensure
  HPC_PIN_ARGS=(--partition="$HPC_PARTITION")
  # NON usare "test && comando" come ultima riga: quando l'exclude e' vuoto
  # (tutti i nodi della partizione sono nel gruppo omogeneo) il test fallisce,
  # la funzione ritorna 1 e il "set -e" del chiamante uccide lo script in
  # silenzio, prima ancora del rilancio via srun.
  if [ -n "$HPC_TARGET_EXCLUDE" ]; then
    HPC_PIN_ARGS+=(--exclude="$HPC_TARGET_EXCLUDE")
  fi
  return 0
}

# Vero se $1 (hostname) appartiene all'insieme ammesso.
hpc_node_in_target() {
  hpc_target_ensure
  [ -n "$HPC_TARGET_EXCLUDE" ] || return 0   # nessuna restrizione
  local host="${1%%.*}" excluded
  excluded="$(_hpc_expand "$HPC_TARGET_EXCLUDE")"
  case ",$excluded," in
    *",$host,"*) return 1 ;;
    *) return 0 ;;
  esac
}

# Inietta il pinning negli script *.dist gia' generati da "btool gen".
#
# Perche' qui e non nel runscript: benchmark-tool sostituisce nel template
# solo {walltime} {cpt} {partition} {jobs} {dist_options}, e dist_options e'
# un attributo PER <setting> (andrebbe ripetuto su tutte e ~15 le varianti,
# e viene splittato sulle virgole — che in una hostlist ci sono). Riscrivere
# gli *.dist subito dopo la generazione e' un punto solo, e vale sia per la
# suite completa sia per lo smoke test.
# Idempotente: se la riga c'e' gia', non la duplica.
pin_dist_scripts() {
  local dir="$1"
  hpc_target_ensure
  [ -n "$HPC_TARGET_EXCLUDE" ] || return 0
  [ -d "$dir" ] || return 0

  local f n=0
  while IFS= read -r f; do
    grep -q '^#SBATCH --exclude=' "$f" && continue
    # inserita subito dopo --partition, cosi' il blocco SBATCH resta leggibile
    sed -i "/^#SBATCH --partition=/a #SBATCH --exclude=$HPC_TARGET_EXCLUDE" "$f"
    n=$((n + 1))
  done < <(find "$dir" -name '*.dist' -type f)
  [ "$n" -gt 0 ] && ok "pinning applicato a $n script *.dist (--exclude=$HPC_TARGET_EXCLUDE)"
  return 0
}

# Copia il lock accanto ai risultati: la campagna si porta dietro il proprio
# certificato di provenienza hardware, senza doverlo ricostruire a posteriori.
record_hpc_target() {
  local out_dir="$1"
  [ -d "$out_dir" ] || return 0
  [ -f "$HPC_TARGET_LOCK" ] && cp -f "$HPC_TARGET_LOCK" "$out_dir/hpc_target.conf"
  return 0
}

# --- eseguito direttamente: inventario + target ---------------
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  echo "Partizione: $HPC_PARTITION"
  echo
  echo "Inventario nodi (nodo | CPUTot | RealMemory | Sockets | CoresPerSocket | ThreadsPerCore | Features):"
  _hpc_node_table | sed 's/\t/  |  /' | sed 's/^/  /'
  echo
  hpc_target_ensure
fi
