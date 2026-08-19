#!/usr/bin/env python3
"""
Ricostruisce, per una campagna GIA' ESEGUITA, su quale nodo SLURM e' finito
ogni singolo run, e mette i tempi a confronto per nodo.

A COSA SERVE
    Il capitolo Risultati dichiara un caveat (sec:node-variance): tre varianti
    BSP che groundano lo stesso identico programma (gc_noheur, la, lc)
    mostrano tempi divergenti del 28% mediano e del 46% a n=140. La causa
    ipotizzata e' l'eterogeneita' dei nodi, perche' i job venivano dispacciati
    indifferentemente su 'kr' e 'kr-big'.

    Da 'scontrol show node' la partizione kr risulta perfettamente omogenea
    (10 nodi identici), quindi restringere la campagna a kr o e' LA soluzione
    - se i run veloci venivano da kr-big - oppure non e' una soluzione
    affatto, e la varianza viene da qualcosa che SLURM non dichiara.

    Le due ipotesi si distinguono senza rilanciare niente: i job SLURM della
    vecchia campagna hanno stampato il proprio hostname in testa a out.%j
    ("running jobs@<host>...") e subito dopo l'elenco dei run che avrebbero
    eseguito. Questo script rilegge quei file e ricostruisce la mappa
    run -> nodo, poi la incrocia con i tempi in runsolver.watcher.

    E' un lavoro forense su dati esistenti: costa secondi e puo' risparmiare
    una campagna intera lanciata contro la causa sbagliata.

USO
    python3 tools/node_forensics.py [--output output] [--tsv nodi_runs.tsv]

    Il report finale e' la tabella che decide: per ogni istanza BSP, i tempi
    delle tre varianti same-encoding affiancati al nodo che le ha eseguite.
    Se la variante veloce sta sistematicamente su un nodo diverso dalle
    altre due, la causa e' il nodo ed e' gia' stata rimossa.
"""

import argparse
import os
import re
import sys
from collections import defaultdict

# "running jobs@kr-node3..." emesso da templates/single.dist
RE_HOST = re.compile(r"^running jobs@(?P<host>\S+?)\.{0,3}\s*$")
# "running  results/BSP/clingo-native-1.0-la/BSP/bsp-120.lp/run1/start.sh"
RE_JOB = re.compile(r"^running\s+(?P<path>\S+start\.sh)\s*$")
# "[runlim] real:		123.45 seconds"
RE_REAL = re.compile(r"^\[runlim\] real:\s*(?P<val>[0-9]+(?:\.[0-9]+)?)")
# "Time         : 205.421s (Solving: 44.80s 1st Model: 44.79s Unsat: 0.00s)"
RE_CLINGO_TIME = re.compile(
    r"^Time\s*:\s*(?P<total>[0-9.]+)s\s*\(Solving:\s*(?P<solving>[0-9.]+)s")
RE_RESULT = re.compile(r"^(SATISFIABLE|UNSATISFIABLE|OPTIMUM FOUND)")

# le tre varianti che groundano lo STESSO programma: e' su queste che il
# caveat si regge, perche' ogni differenza di tempo fra loro e' rumore
SAME_ENCODING = ("gc_noheur", "la", "lc")

# Varianti GROUND: i due backend eseguono encoding byte-identici sullo stesso
# solver (v. capitolo Risultati). Sono la sonda migliore che esista per
# confrontare due NODI, perche' tengono fisso il carico di lavoro: se lo
# stesso identico programma impiega lo stesso tempo su due nodi diversi, i
# nodi sono equivalenti, punto. Le varianti lazy no: li' i due backend fanno
# lavoro diverso (propagatore C++ contro motore SWI-Prolog).
GROUND_SETTINGS = ("gc", "gc_noheur", "ga", "ga_weak")


def parse_out_files(output_dir):
    """run_dir assoluto -> hostname, leggendo gli out.%j di ogni project."""
    mapping = {}
    for project in sorted(os.listdir(output_dir)):
        hpc_dir = os.path.join(output_dir, project, "hpc")
        if not os.path.isdir(hpc_dir):
            continue
        for name in sorted(os.listdir(hpc_dir)):
            if not name.startswith("out."):
                continue
            host = None
            with open(os.path.join(hpc_dir, name), errors="replace") as fh:
                for line in fh:
                    m = RE_HOST.match(line.strip())
                    if m:
                        host = m.group("host")
                        continue
                    m = RE_JOB.match(line.strip())
                    if m and host:
                        run_dir = os.path.normpath(
                            os.path.join(hpc_dir, os.path.dirname(m.group("path")))
                        )
                        mapping[run_dir] = host
    return mapping


def describe(run_dir, output_dir):
    """Estrae (project, benchmark, system, setting, istanza) dal percorso.

    Layout di benchmark-tool (v. Runspec.path e ScriptGen._path):
        <output>/<project>/<machine>/results/<benchmark>/
            <system>-<version>-<setting>/<benchclass>/<istanza>/run<N>

    <benchclass> pero' NON produce sempre un livello: per le istanze che
    stanno direttamente in benchmarks/<FAM>/ il suo nome e' ".", che
    os.path.normpath fa sparire. Contando da sinistra si finiva percio' a
    leggere "run1" come nome dell'istanza, e tutte le istanze di una famiglia
    collassavano in un'unica cella - cioe' il confronto "stesso programma,
    tempi diversi" veniva fatto fra programmi diversi. L'istanza si prende
    dal fondo, dove la posizione e' fissa in entrambi i casi.
    """
    rel = os.path.relpath(run_dir, output_dir).split(os.sep)
    try:
        i = rel.index("results")
    except ValueError:
        return None
    if len(rel) < i + 4:
        return None
    project = rel[0]
    benchmark = rel[i + 1]
    sysdir = rel[i + 2]
    instance = rel[-2]          # rel[-1] e' sempre "run<N>"
    # "clingo-native-1.0-la" -> system "clingo-native", setting "la"
    parts = sysdir.rsplit("-", 1)
    setting = parts[1] if len(parts) == 2 else sysdir
    system = parts[0].rsplit("-", 1)[0] if len(parts) == 2 else sysdir
    return project, benchmark, system, setting, instance


def measure(run_dir):
    """(real, grounding, solving, stato) del run.

    stato: ok | timeout | memout | incompleto | ignoto.

    Il filtro sullo stato non e' un dettaglio: un timeout riporta ~601s per
    costruzione, e infilarlo in un confronto di tempi produce "scarti" del
    300% che non misurano niente. Serve anche 'incompleto': un run che muore
    senza che runlim dichiari ne' timeout ne' memout (tipicamente ucciso
    dall'OOM-killer di sistema, che sui nodi kr ha solo ~1.9 GB di margine
    sopra il memout) ha un tempo che sembra normale e non lo e'. Si
    riconosce dall'assenza della riga di risultato di clingo.

    grounding = Time - Solving nella riga di statistiche di clingo: e'
    esattamente la quantita' su cui si regge il caveat sec:node-variance.
    """
    watcher = os.path.join(run_dir, "runsolver.watcher")
    solver = os.path.join(run_dir, "runsolver.solver")
    if not os.path.isfile(watcher):
        return None, None, None, "ignoto"

    real, status = None, "ok"
    with open(watcher, errors="replace") as fh:
        for line in fh:
            m = RE_REAL.match(line)
            if m:
                real = float(m.group("val"))
            if "out of time" in line:
                status = "timeout"
            elif "out of memory" in line:
                status = "memout"

    total = solving = None
    solved = False
    if os.path.isfile(solver):
        with open(solver, errors="replace") as fh:
            for line in fh:
                m = RE_CLINGO_TIME.match(line)
                if m:
                    total = float(m.group("total"))
                    solving = float(m.group("solving"))
                if RE_RESULT.match(line):
                    solved = True
    if status == "ok" and not solved:
        status = "incompleto"

    grounding = round(total - solving, 3) if (total is not None and solving is not None) else None
    return real, grounding, solving, status


def instance_key(name):
    """Ordina bsp-20.lp prima di bsp-100.lp invece che lessicograficamente."""
    m = re.search(r"(\d+)", name)
    return (int(m.group(1)) if m else 0, name)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--output", default="output",
                    help="cartella di output della campagna (default: output)")
    ap.add_argument("--tsv", default=None,
                    help="scrive il dettaglio run-per-run in questo file TSV")
    args = ap.parse_args()

    if not os.path.isdir(args.output):
        sys.exit(f"cartella non trovata: {args.output}")

    mapping = parse_out_files(args.output)
    if not mapping:
        sys.exit(
            f"nessun out.%j interpretabile sotto {args.output}/*/hpc/.\n"
            "La campagna e' stata cancellata da un 'btool gen -c', oppure gli\n"
            "out.%j sono stati rimossi: senza quelli la mappa run->nodo non e'\n"
            "ricostruibile a posteriori."
        )

    rows = []
    for run_dir, host in mapping.items():
        d = describe(run_dir, args.output)
        if d is None:
            continue
        real, grounding, solving, status = measure(run_dir)
        rows.append((host, *d, real, grounding, solving, status))

    print(f"Run con nodo ricostruito: {len(rows)}")
    hosts = defaultdict(int)
    for r in rows:
        hosts[r[0]] += 1
    print(f"Nodi distinti: {len(hosts)}")
    for h, n in sorted(hosts.items(), key=lambda kv: -kv[1]):
        print(f"  {n:5d}  {h}")

    if args.tsv:
        with open(args.tsv, "w") as fh:
            fh.write("nodo\tproject\tbenchmark\tsystem\tsetting\tistanza"
                     "\treal_s\tgrounding_s\tsolving_s\tstato\n")
            for r in sorted(rows):
                fh.write("\t".join("" if x is None else str(x) for x in r) + "\n")
        print(f"\nDettaglio run-per-run -> {args.tsv}")

    # --- IL test sui nodi: stesso programma, nodi diversi ----------------
    # Le varianti ground girano encoding byte-identici sui due backend. Se lo
    # stesso programma, groundato dallo stesso solver, impiega tempi diversi
    # su nodi diversi, allora i nodi non sono equivalenti. Se impiega lo
    # stesso tempo, non lo sono e basta: qualunque scarto osservato altrove
    # ha un'altra causa. E' l'unico confronto del dataset in cui il carico di
    # lavoro e' tenuto fisso e a variare e' solo la macchina.
    print("\n" + "=" * 78)
    print("CONTROLLO SUI NODI: stesso programma ground, backend diversi")
    print("(encoding byte-identici -> ogni differenza e' la macchina)")
    print("=" * 78)

    ground = defaultdict(dict)
    for host, _p, benchmark, system, setting, instance, real, grd, _slv, status in rows:
        if setting not in GROUND_SETTINGS or status != "ok" or grd is None:
            continue
        ground[(benchmark, setting, instance)][system] = (host, real, grd)

    diffs = []
    for key in sorted(ground, key=lambda k: (k[0], k[1], instance_key(k[2]))):
        cell = ground[key]
        if len(cell) < 2:
            continue
        (s1, (h1, r1, g1)), (s2, (h2, r2, g2)) = sorted(cell.items())
        if h1 == h2 or min(g1, g2) <= 1.0:   # stesso nodo, o troppo piccolo
            continue
        d = abs(g1 - g2) / min(g1, g2) * 100
        diffs.append(d)
        mark = "  <== " if d >= 10 else ""
        print(f"\n{key[0]} {key[1]} {key[2]}   grounding differisce {d:5.1f}%{mark}")
        print(f"    {s1:<14} grounding {g1:8.1f}s   totale {r1:8.1f}s   {h1}")
        print(f"    {s2:<14} grounding {g2:8.1f}s   totale {r2:8.1f}s   {h2}")

    def median(xs):
        xs = sorted(xs)
        n = len(xs)
        if not n:
            return float("nan")
        return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2

    if diffs:
        print(f"\n  {len(diffs)} coppie stesso-programma/nodi-diversi:")
        print(f"    differenza mediana di GROUNDING fra nodi: {median(diffs):.1f}%")
        print(f"    massima:                                  {max(diffs):.1f}%")
        print("  Questo numero E' la varianza inter-nodo, misurata invece che ipotizzata.")
    else:
        print("  nessuna coppia utilizzabile.")

    # --- la tabella che decide ------------------------------------------
    # Stesso programma groundato, tre varianti: ogni scarto e' rumore, e la
    # domanda e' se il rumore segue il nodo.
    print("\n" + "=" * 78)
    print("BSP, varianti same-encoding (" + ", ".join(SAME_ENCODING) + "):")
    print("stesso programma groundato -> i tempi dovrebbero coincidere.")
    print("Solo run COMPLETATI: timeout e memout non misurano la macchina.")
    print("=" * 78)

    by_cell = defaultdict(dict)
    for host, _project, benchmark, system, setting, instance, real, grd, _slv, status in rows:
        if benchmark != "BSP" or setting not in SAME_ENCODING:
            continue
        if status != "ok" or grd is None:
            continue
        by_cell[(system, instance)][setting] = (host, real, grd)

    if not by_cell:
        print("nessun run BSP same-encoding completato trovato.")
        return

    for system, instance in sorted(by_cell, key=lambda k: (k[0], instance_key(k[1]))):
        cell = by_cell[(system, instance)]
        got = [(s, *cell[s]) for s in SAME_ENCODING if s in cell]
        if len(got) < 2:
            continue
        gs = [g for _s, _h, _r, g in got]
        lo = min(gs)
        if lo <= 1.0:
            continue
        nodes = {h for _s, h, _r, _g in got}
        spread = (max(gs) - lo) / lo * 100
        flag = ""
        if spread >= 15:
            flag = "  <== UN SOLO nodo" if len(nodes) == 1 else "  <== nodi DIVERSI"
        print(f"\n{system}  {instance}   grounding: scarto {spread:5.1f}%{flag}")
        for s, h, r, g in got:
            print(f"    {s:<10} grounding {g:8.1f}s   totale {r:8.1f}s   {h}")

    print("\n" + "-" * 78)
    print("COME SI LEGGE")
    print("  Il caveat sec:node-variance riguarda il GROUNDING, non il totale:")
    print("  il totale si separa anche per motivi veri (il solving di 'la' e'")
    print("  ~0, quello di 'gc_noheur' decine di secondi), e confonderlo con")
    print("  il rumore di macchina fa attribuire al nodo un risultato della tesi.")
    print("  Il numero da guardare e' la differenza mediana di grounding del")
    print("  blocco 'CONTROLLO SUI NODI' qui sopra: li' il programma e' identico")
    print("  e a cambiare c'e' solo la macchina.")


if __name__ == "__main__":
    main()
