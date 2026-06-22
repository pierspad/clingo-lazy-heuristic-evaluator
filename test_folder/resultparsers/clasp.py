"""
Resultparser custom per la tesi "Lazy Heuristics / Dynamic Aggregates".

Sovrascrive il resultparser `clasp` di default di benchmark-tool (per essere
selezionato basta `measures="clasp"` sui system + questo file in
./resultparsers/). Estende il parser ufficiale con:

  * tempo di SOLVING e GROUNDING derivati dalle statistiche clingo
    (Time: total (Solving: ...)) -> il grounding e' total - solving;
  * conteggi strutturali clingo: rules, variables, atoms, constraints;
  * metriche del propagatore query-driven dal backend prolog, estratte dalla
    riga `[lazy-prolog] summary key=value ...` su stderr
    (decide_calls, tempi di decide/sync/query/scan/lookup/selection,
    candidate seen/max/avg);
  * flag di sanity `lazy_active`: intercetta il fallback silenzioso di una
    variante lazy (l*) sul backend prolog quando l'euristica NON ha mai deciso
    (decide_calls assente o 0) -> "inactive".

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

# Riga di riepilogo del backend prolog (emessa solo con LAZY_PROLOG_STATS=1).
SUMMARY_PREFIX = "[lazy-prolog] summary "
LAZY_FIELDS = (
    "decide_calls",
    "total_decide_time_ms",
    "total_state_sync_time_ms",
    "total_prolog_query_time_ms",
    "total_candidate_scan_time_ms",
    "total_literal_lookup_time_ms",
    "total_candidate_selection_time_ms",
    "total_candidates_seen",
    "max_candidates_seen",
    "avg_candidates_per_decide",
)

# penalized-average-runtime score constant
PAR = 2


def _parse_lazy_summary(line: str) -> dict[str, float]:
    """Estrae le coppie key=value dalla riga `[lazy-prolog] summary ...`."""
    out: dict[str, float] = {}
    payload = line.strip()[len(SUMMARY_PREFIX):]
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
                    # Riepilogo propagatore prolog (puo' comparire una sola volta).
                    if line.startswith(SUMMARY_PREFIX):
                        lazy = _parse_lazy_summary(line)
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

    # --- Metriche del propagatore prolog -------------------------------------
    for field in LAZY_FIELDS:
        if field in lazy:
            result[field] = ("float", lazy[field])

    # --- Flag di sanity: euristica lazy attiva? ------------------------------
    # variante = nome del setting (la, lc, la_aux, ...); la prima lettera 'l'
    # indica l'approccio lazy. is_prolog = il system e' il backend prolog.
    variant = str(runspec.setting.name).lower()
    is_lazy = variant.startswith("l")
    is_prolog = "prolog" in str(runspec.system.name).lower()
    if is_lazy and is_prolog:
        decide_calls = lazy.get("decide_calls", 0.0)
        result["lazy_active"] = ("string", "active" if decide_calls > 0 else "inactive")

    return result
