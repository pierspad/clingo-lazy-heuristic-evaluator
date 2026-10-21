"""
Resultparser custom per la tesi "Lazy Heuristics / Dynamic Aggregates".

Sovrascrive il resultparser `clasp` di default di benchmark-tool (per essere
selezionato basta `measures="clasp"` sui system + questo file in
./resultparsers/). Estende il parser ufficiale con:

  * tempo di SOLVING e GROUNDING derivati dalle statistiche clingo
    (Time: total (Solving: ...)) -> il grounding e' total - solving;
  * conteggi strutturali clingo: rules, variables, atoms, constraints;
  * metriche del propagatore, estratte dalla riga di summary su stderr —
    `[lazy-prolog] summary key=value ...` per il backend SWI-Prolog e
    `[lazy-native] summary key=value ...` per il backend C++ (decide_calls,
    tempi di decide/sync/scan, candidate seen/max/avg), piu' la derivata
    `ms_per_decide` comune ai due;
  * flag di sanity `lazy_active`: intercetta il fallback silenzioso di una
    variante lazy (l*) quando l'euristica NON ha mai deciso (decide_calls
    assente o 0) -> "inactive". Vale per entrambi i backend.

La memoria di picco (`mem`, da runlim `space`) e' misurata sull'UNICO processo
clingo che grounda E risolve: cattura quindi anche l'esplosione di grounding
delle varianti ground-and-solve (g*), che e' il fenomeno centrale del lavoro.

Le metriche di conteggio del grounding delle euristiche (quante righe
`#heuristic` / fatti `__heuristic` vengono materializzate) NON sono qui: sono
un passo `--text` separato, pesante in memoria, che falserebbe `mem`. Vivono
nello strumento disaccoppiato `tools/ground_counts.py`.
"""

import os
import re
import sys
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from benchmarktool.runscript import runscript  # nocoverage

# ----------------------------------------------------------------------------
# Espressioni regolari "riga -> valore singolo" (come il parser ufficiale).
# ----------------------------------------------------------------------------
clasp_re = {
    "models": ("float", re.compile(r"^(c )?Models[ ]*:[ ]*(?P<val>[0-9]+)\+?[ ]*$")),
    "choices": ("float", re.compile(r"^(c )?Choices[ ]*:[ ]*(?P<val>[0-9]+)\+?.*$")),
    "time": ("float", re.compile(r"^\[runlim\] real:\s*(?P<val>[0-9]+(\.[0-9]+)?)")),
    "conflicts": ("float", re.compile(r"^(c )?Conflicts[ ]*:[ ]*(?P<val>[0-9]+)\+?.*$")),
    "restarts": ("float", re.compile(r"^(c )?Restarts[ ]*:[ ]*(?P<val>[0-9]+)\+?.*$")),
    "rules": ("float", re.compile(r"^(c )?Rules[ ]*:[ ]*(?P<val>[0-9]+).*$")),
    "variables": ("float", re.compile(r"^(c )?Variables[ ]*:[ ]*(?P<val>[0-9]+).*$")),
    "atoms": ("float", re.compile(r"^(c )?Atoms[ ]*:[ ]*(?P<val>[0-9]+).*$")),
    "constraints": ("float", re.compile(r"^(c )?Constraints[ ]*:[ ]*(?P<val>[0-9]+).*$")),
    "optimum": ("string", re.compile(r"^(c )?Optimization[ ]*:[ ]*(?P<val>(-?[0-9]+)( -?[0-9]+)*)[ ]*$")),
    "status": ("string", re.compile(r"^(s )?(?P<val>SATISFIABLE|UNSATISFIABLE|UNKNOWN|OPTIMUM FOUND)[ ]*$")),
    "interrupted": ("string", re.compile(r"(c )?(?P<val>INTERRUPTED)")),
    "error": ("string", re.compile(r"^\*\*\* (clasp|clingo) ERROR: (?P<val>.*)$")),
    "rstatus": ("string", re.compile(r"^\[runlim\] status:\s*(?P<val>.*)$")),
    "mem": ("float", re.compile(r"^\[runlim\] space:\s*(?P<val>[0-9]+(\.[0-9]+)?) MB")),
}

# `Time : 0.123s (Solving: 0.05s 1st Model: ...)` -> total + solving.
TIME_RE = re.compile(
    r"^Time[ ]*:[ ]*(?P<total>[0-9]+(?:\.[0-9]+)?)s\s*\(Solving:\s*(?P<solving>[0-9]+(?:\.[0-9]+)?)s"
)

# Righe di riepilogo del propagatore, emesse su stderr con
# LAZY_HEURISTIC_STATS=1 (alias storico: LAZY_PROLOG_STATS=1). Entrambi i
# backend usano lo stesso formato `key=value` e le stesse chiavi dove la
# metrica ha lo stesso significato, cambia solo il prefisso:
#   [lazy-prolog] summary ...  -> backend SWI-Prolog in-process
#   [lazy-native] summary ...  -> backend C++ puro
# In questo modo le misure del propagatore NON sono piu' "solo prolog": si
# confrontano fra backend senza casi speciali nei grafici. Restano
# intrinsecamente prolog-only le voci legate alla query esterna
# (total_prolog_query_time_ms, total_literal_lookup_time_ms,
# total_candidate_selection_time_ms), perche' nel backend native non esiste
# alcun motore da interrogare: e' una differenza reale fra i due disegni, non
# una lacuna di misura.
SUMMARY_PREFIXES = ("[lazy-prolog] summary ", "[lazy-native] summary ")
LAZY_FIELDS = (
    # comuni ai due backend
    "decide_calls",
    "total_decide_time_ms",
    "total_state_sync_time_ms",
    "total_candidate_scan_time_ms",
    "total_candidates_seen",
    "max_candidates_seen",
    "avg_candidates_per_decide",
    # solo prolog (query verso il motore esterno)
    "total_prolog_query_time_ms",
    "total_literal_lookup_time_ms",
    "total_candidate_selection_time_ms",
    # solo native (contatori del propagatore in-memory)
    "decide_hits",
    "propagate_calls",
    "undo_calls",
)

# penalized-average-runtime score constant
PAR = 2


def _summary_payload(line: str) -> str | None:
    """Se `line` e' una riga di summary del propagatore rende la parte
    `key=value ...`, altrimenti None (qualunque sia il backend che l'ha
    emessa)."""
    for prefix in SUMMARY_PREFIXES:
        if line.startswith(prefix):
            return line.strip()[len(prefix):]
    return None


def _parse_lazy_summary(payload: str) -> dict[str, float]:
    """Estrae le coppie key=value dal payload di una riga di summary."""
    out: dict[str, float] = {}
    for part in payload.split():
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        if key in LAZY_FIELDS:
            try:
                out[key] = float(value)
            except ValueError:
                pass
    return out


# pylint: disable=unused-argument
def parse(
    path: str, runspec: "runscript.Runspec", instance: "runscript.Benchmark.Instance", run: int
) -> dict[str, tuple[str, Any]]:
    """
    Estrae le statistiche di un singolo run.

    Args:
        path:     directory del run (contiene runsolver.solver / runsolver.watcher).
        runspec:  specifica del run (system, setting, project.job, ...).
        instance: istanza di benchmark.
        run:      numero del run.

    Returns:
        dict {nome: (tipo, valore)} con tipo in {"float", "string"}.
    """
    timeout = runspec.project.job.timeout
    res: dict[str, tuple[str, Any]] = {"time": ("float", timeout)}
    lazy: dict[str, float] = {}

    for f in ["runsolver.solver", "runsolver.watcher"]:
        try:
            with open(os.path.join(path, f), errors="ignore", encoding="utf-8") as file:
                for line in file:
                    # Riepilogo del propagatore (native o prolog): puo'
                    # comparire una sola volta, alla distruzione del propagatore.
                    payload = _summary_payload(line)
                    if payload is not None:
                        lazy = _parse_lazy_summary(payload)
                        continue
                    # Time: total (Solving: ...).
                    mt = TIME_RE.match(line)
                    if mt:
                        total = float(mt.group("total"))
                        solving = float(mt.group("solving"))
                        res["clingo_total"] = ("float", total)
                        res["solving"] = ("float", solving)
                        res["grounding"] = ("float", max(total - solving, 0.0))
                        continue
                    # Tutte le altre metriche riga->valore.
                    for val, reg in clasp_re.items():
                        m = reg[1].match(line)
                        if m:
                            res[val] = (
                                reg[0],
                                float(m.group("val")) if reg[0] == "float" else m.group("val"),
                            )
        except FileNotFoundError:
            sys.stderr.write(
                f"*** WARNING: Result file '{f}' not found for run {run} of instance '{instance.name}' "
                f"for system '{runspec.system.name}-{runspec.system.version}'! ({path})\n"
            )

    # --- Stati di errore / timeout / memout ----------------------------------
    # runlim segnala esplicitamente sia il timeout ("out of time") sia il memout
    # ("out of memory"). Li sfruttiamo per NON confondere un timeout pulito con
    # un errore del solver: un run ucciso al limite di tempo non stampa lo
    # status di clingo, quindi con la logica originale (`"status" not in res`)
    # finirebbe marcato come error=1 oltre che timeout=1, inquinando i conteggi.
    if "rstatus" in res and res["rstatus"][1] == "out of memory":
        res["error"] = ("string", "std::bad_alloc")
        res["status"] = ("string", "UNKNOWN")

    rstatus = res["rstatus"][1] if "rstatus" in res else ""
    hit_time_limit = "out of time" in rstatus or res["time"][1] >= timeout
    memout = "error" in res and res["error"][1] == "std::bad_alloc"
    solver_error = "error" in res and res["error"][1] != "std::bad_alloc"

    result: dict[str, tuple[str, Any]] = {}
    # Errore VERO = clingo ha emesso un errore non-di-memoria, oppure il run e'
    # morto senza status pur NON essendo un timeout/memout (crash reale).
    error = solver_error or ("status" not in res and not hit_time_limit and not memout)
    status = res["status"][1] if "status" in res else None
    timedout = (
        hit_time_limit
        or memout
        or error
        or status == "UNKNOWN"
        or (status == "SATISFIABLE" and "optimum" in res)
        or "interrupted" in res
    )
    if timedout:
        res["time"] = ("float", timeout)
    if error:
        sys.stderr.write(
            f"*** WARNING: Run {run} of instance '{instance.name}' "
            f"for system '{runspec.system.name}-{runspec.system.version}' "
            f"failed with unrecognized status or error! ({path})\n"
        )
    result["error"] = ("float", int(error))
    result["timeout"] = ("float", int(timedout))
    result["memout"] = ("float", int(memout))

    if "optimum" in res and " " not in res["optimum"][1]:
        result["optimum"] = ("float", float(res["optimum"][1]))
        del res["optimum"]
    for transient in ("interrupted", "error", "rstatus"):
        res.pop(transient, None)

    for key, value in res.items():
        result[key] = (value[0], value[1])

    # --- Metriche del propagatore (native o prolog) --------------------------
    for field in LAZY_FIELDS:
        if field in lazy:
            result[field] = ("float", lazy[field])

    # Derivata comune ai due backend: costo medio di UNA decisione del
    # propagatore. E' la metrica che rende confrontabili i due disegni
    # (in-memory vs query a SWI) a parita' di lavoro svolto, indipendentemente
    # da quante decisioni la ricerca abbia poi richiesto.
    decide_calls = lazy.get("decide_calls", 0.0)
    if decide_calls > 0 and "total_decide_time_ms" in lazy:
        result["ms_per_decide"] = ("float", lazy["total_decide_time_ms"] / decide_calls)

    # --- Flag di sanity: euristica lazy attiva? ------------------------------
    # variante = nome del setting (la, lc, la_aux, ...); la prima lettera 'l'
    # indica l'approccio lazy. Ora che ANCHE il backend native emette il
    # summary, il flag vale per entrambi i system: un l* che non ha mai deciso
    # e' un fallback silenzioso su gc_noheur, e va intercettato ovunque.
    variant = str(runspec.setting.name).lower()
    if variant.startswith("l"):
        result["lazy_active"] = ("string", "active" if decide_calls > 0 else "inactive")

    return result
