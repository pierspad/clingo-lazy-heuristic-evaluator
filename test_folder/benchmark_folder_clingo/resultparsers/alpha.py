"""
Resultparser per il solver ALPHA (Qh) nella suite "Lazy Heuristics /
Dynamic Aggregates". Selezionato da `measures="alpha"` sul <system>.

PERCHE' UN PARSER SEPARATO E NON UN RAMO DENTRO clasp.py
Alpha non e' clingo: non stampa "Choices"/"Conflicts"/"Models", non ha una
riga "Time: total (Solving: ...)" e non separa grounding da solving --- il
lazy grounding li interleava per costruzione, quindi quella separazione
non esiste proprio come grandezza misurabile. Tenere i due parser distinti
evita di far finta che esista.

COSA E' CONFRONTABILE CON CLINGO E COSA NO
Nelle colonne COMUNI finisce solo cio' che misura la stessa grandezza
fisica sui due sistemi, e che viene per giunta dallo stesso strumento
(runlim, esterno al solver):

    time    wall-clock del processo          [runlim real]
    mem     picco di RSS del processo        [runlim space]
    status / timeout / memout / error

Tutti i contatori interni di Alpha vivono invece in colonne `alpha_*`.
NON sono mappati su choices/conflicts di clasp: `bt` (backtrack) e
`conflicts` non contano la stessa cosa, e `g` (chiamate al grounder) non
ha alcun corrispettivo in un sistema che grounda tutto una volta sola.
Equipararli renderebbe i grafici piu' facili da disegnare e le conclusioni
indifendibili.

CAVEAT SULLA MEMORIA, da dichiarare in tesi
`mem` e' RSS di picco del processo, e per Alpha il processo e' una JVM:
include l'heap che la JVM ha RISERVATO, non solo quello che usa davvero.
Il confronto di memoria con clingo va quindi letto come "quanto costa
eseguire questo sistema", non "quanto stato tiene l'algoritmo". Il wrapper
programs/alpha-qh-1.0 fissa -Xmx sotto il memout di runlim proprio perche'
un OOM della JVM si presenti come memout pulito e non come crash.
"""

import os
import re
import sys
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from benchmarktool.runscript import runscript  # nocoverage

# ----------------------------------------------------------------------------
# Misure esterne (runlim) + esito. Identiche a quelle del parser clingo:
# e' lo stesso strumento a produrle, ed e' questo che rende time/mem
# confrontabili fra i due sistemi.
# ----------------------------------------------------------------------------
runlim_re = {
    "time": ("float", re.compile(r"^\[runlim\] real:\s*(?P<val>[0-9]+(\.[0-9]+)?)")),
    "mem": ("float", re.compile(r"^\[runlim\] space:\s*(?P<val>[0-9]+(\.[0-9]+)?) MB")),
    "rstatus": ("string", re.compile(r"^\[runlim\] status:\s*(?P<val>.*)$")),
    "status": ("string", re.compile(r"^\s*(?P<val>SATISFIABLE|UNSATISFIABLE)\s*$")),
}

# Riga di statistiche del solver, emessa da -st. Esempio:
#   g=200, bt=0, bj=0, bt_within_bj=0, mbt=0, cac=0, del_ng=0
# g   = GUESS (scelte del solver). Verificato sul sorgente di Alpha:
#       SolverMaintainingStatistics.getStatisticsString() stampa
#       "g=" + getNumberOfChoices(), e il test lo chiama expectedNumberOfGuesses.
#       NON sono chiamate al grounder: quelle Alpha non le espone su questa riga.
# bt  = backtrack, bj = backjump, mbt = must-be-true
# cac = choices after conflict, del_ng = nogood cancellati
SOLVER_STATS_RE = re.compile(
    r"^g=(?P<g>[0-9]+),\s*bt=(?P<bt>[0-9]+),\s*bj=(?P<bj>[0-9]+),"
    r"\s*bt_within_bj=(?P<bt_within_bj>[0-9]+),\s*mbt=(?P<mbt>[0-9]+),"
    r"\s*cac=(?P<cac>[0-9]+),\s*del_ng=(?P<del_ng>[0-9]+)"
)

# Statistiche del motore Prolog che valuta le euristiche (-uqh):
#   add time=40 ms, remove time=0 ms, query time=1951 ms, total time=1991 ms
#   total queries=200, non empty queries=200
# Sono l'analogo diretto delle metriche per-decisione del propagatore di
# questa tesi: "add/remove time" e' la sincronizzazione dello stato,
# "query time" e' la valutazione dell'euristica.
PROLOG_TIMES_RE = re.compile(
    r"^add time=(?P<add>[0-9]+) ms,\s*remove time=(?P<remove>[0-9]+) ms,"
    r"\s*query time=(?P<query>[0-9]+) ms,\s*total time=(?P<total>[0-9]+) ms"
)
PROLOG_QUERIES_RE = re.compile(
    r"^total queries=(?P<total>[0-9]+),\s*non empty queries=(?P<nonempty>[0-9]+)"
)

# Un crash della JVM non assomiglia a un errore di clingo: niente
# "*** clingo ERROR", solo uno stack trace. OutOfMemoryError va tenuto
# distinto da un errore vero, esattamente come std::bad_alloc nel parser
# clingo: e' un memout, cioe' un dato, non un guasto.
JAVA_OOM_RE = re.compile(r"java\.lang\.OutOfMemoryError")
JAVA_EXC_RE = re.compile(r"^Exception in thread \S+ (?P<val>\S+)")
ALPHA_ERR_RE = re.compile(r"^\*\*\* alpha ERROR: (?P<val>.*)$")


def parse(
    path: str, runspec: "runscript.Runspec", instance: "runscript.Benchmark.Instance", run: int
) -> dict[str, tuple[str, Any]]:
    """Estrae le statistiche di un singolo run di Alpha.

    Args:
        path:     directory del run (runsolver.solver / runsolver.watcher).
        runspec:  specifica del run (system, setting, project.job, ...).
        instance: istanza di benchmark.
        run:      numero del run.

    Returns:
        dict {nome: (tipo, valore)} con tipo in {"float", "string"}.
    """
    timeout = runspec.project.job.timeout
    res: dict[str, tuple[str, Any]] = {"time": ("float", timeout)}
    alpha: dict[str, float] = {}
    java_oom = False
    java_exc: str | None = None
    alpha_err: str | None = None

    for f in ["runsolver.solver", "runsolver.watcher"]:
        try:
            with open(os.path.join(path, f), errors="ignore", encoding="utf-8") as file:
                for line in file:
                    m = SOLVER_STATS_RE.match(line)
                    if m:
                        for key, value in m.groupdict().items():
                            alpha[key] = float(value)
                        continue
                    m = PROLOG_TIMES_RE.match(line)
                    if m:
                        alpha["prolog_add_ms"] = float(m.group("add"))
                        alpha["prolog_remove_ms"] = float(m.group("remove"))
                        alpha["prolog_query_ms"] = float(m.group("query"))
                        alpha["prolog_total_ms"] = float(m.group("total"))
                        continue
                    m = PROLOG_QUERIES_RE.match(line)
                    if m:
                        alpha["prolog_queries"] = float(m.group("total"))
                        alpha["prolog_nonempty_queries"] = float(m.group("nonempty"))
                        continue
                    if JAVA_OOM_RE.search(line):
                        java_oom = True
                        continue
                    m = JAVA_EXC_RE.match(line)
                    if m:
                        java_exc = m.group("val")
                        continue
                    m = ALPHA_ERR_RE.match(line)
                    if m:
                        alpha_err = m.group("val")
                        continue
                    for val, reg in runlim_re.items():
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

    # --- esito ---------------------------------------------------------------
    # Stessa logica del parser clingo, cosi' che le colonne timeout/memout/error
    # significhino la stessa cosa nei due sistemi e i grafici di copertura
    # siano leggibili insieme. Le uniche differenze sono le SORGENTI del
    # segnale di memout: runlim ("out of memory") oppure la JVM
    # (OutOfMemoryError), che runlim non vede perche' la JVM muore per conto
    # suo restando sotto il limite di RSS.
    rstatus = res["rstatus"][1] if "rstatus" in res else ""
    memout = java_oom or rstatus == "out of memory"
    hit_time_limit = "out of time" in rstatus or res["time"][1] >= timeout
    status = res["status"][1] if "status" in res else None

    # Errore VERO = eccezione Java che non sia OOM, errore del wrapper, oppure
    # run finito senza status pur non essendo ne' timeout ne' memout.
    solver_error = alpha_err is not None or (java_exc is not None and not java_oom)
    error = solver_error or (status is None and not hit_time_limit and not memout)

    timedout = hit_time_limit or memout or error or status is None
    if timedout:
        res["time"] = ("float", timeout)
    if memout and status is None:
        res["status"] = ("string", "UNKNOWN")

    if error:
        detail = alpha_err or java_exc or "nessuno status riconosciuto"
        sys.stderr.write(
            f"*** WARNING: Run {run} of instance '{instance.name}' "
            f"for system '{runspec.system.name}-{runspec.system.version}' "
            f"failed: {detail} ({path})\n"
        )

    result: dict[str, tuple[str, Any]] = {
        "error": ("float", int(error)),
        "timeout": ("float", int(timedout)),
        "memout": ("float", int(memout)),
    }
    res.pop("rstatus", None)
    for key, value in res.items():
        result[key] = (value[0], value[1])

    # --- contatori specifici di Alpha ---------------------------------------
    for key, value in alpha.items():
        result[f"alpha_{key}"] = ("float", value)

    # Derivata: costo medio di UNA consultazione dell'euristica. E' la
    # grandezza omologa a `ms_per_decide` del propagatore di questa tesi, ed
    # e' l'unico modo onesto di confrontare il costo per-decisione di Alpha
    # con quello dei due backend lazy: rapporta il tempo al lavoro svolto,
    # non al numero di decisioni che la ricerca ha poi richiesto.
    queries = alpha.get("prolog_queries", 0.0)
    if queries > 0 and "prolog_query_ms" in alpha:
        result["alpha_ms_per_query"] = ("float", alpha["prolog_query_ms"] / queries)

    # --- flag di sanity: l'euristica ha davvero deciso? ----------------------
    # Simmetrico a `lazy_active` del parser clingo, e per lo stesso motivo:
    # un Alpha lanciato senza -uqh (o con -ids) termina benissimo e produce
    # risposte corrette, semplicemente senza euristica. In un benchmark quel
    # run non e' un errore, e' un dato che non significa quello che sembra.
    # Il setting `alpha_noheur` E' quel caso, di proposito, quindi lo si
    # verifica solo sui setting che l'euristica dovrebbero usarla.
    variant = str(runspec.setting.name).lower()
    if not variant.endswith("noheur"):
        result["alpha_heuristic_active"] = ("string", "active" if queries > 0 else "inactive")

    return result
