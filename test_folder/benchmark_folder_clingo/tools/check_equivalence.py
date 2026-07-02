#!/usr/bin/env python3
"""
HARNESS DI CORRETTEZZA / EQUIVALENZA DELLE EURISTICHE LAZY
==========================================================
Le euristiche (sia le #heuristic ground dello standard, sia quelle lazy
native/prolog) devono SOLO guidare la ricerca: non possono cambiare
l'insieme delle soluzioni. Questo script verifica proprio questo, ed e' la
sanity-check piu' importante della pipeline (prima mancava del tutto).

Cosa controlla
--------------
1) BSP, n piccolo (default 6) -> EQUIVALENZA ESAUSTIVA.
   Enumera TUTTI gli answer set (clingo -n 0) per ogni variante e per
   entrambi i backend, e verifica che la collezione di answer set sia
   identica:
     - tra varianti dello stesso backend (gc_noheur, gc, ga, la, lc, ...);
     - tra backend native e prolog per la stessa variante.
   Una divergenza qui = bug d'encoding (un'euristica che altera le
   soluzioni) -> ERRORE.

2) Guida della ricerca + wiring del backend prolog.
   Conta le `choices` (a seed fisso, -n 1) di ogni variante. Verifica:
     - che ogni variante lazy prolog abbia `decide_calls > 0`, cioe' che il
       propagatore SWI-Prolog sia DAVVERO entrato in azione (prova diretta).
       decide_calls assente/0 = fallback silenzioso al backend ausiliario
       (ricerca senza euristica) -> ERRORE. Sul backend native decide_calls
       non e' instrumentato, quindi la guida li' si verifica via choices;
     - che `la` (lazy alpha) guidi davvero, cioe' faccia MENO choices di
       gc_noheur su BSP (dove la guida e' attesa) -> ERRORE se non guida;
     - che native-`la` e prolog-`la` facciano lo STESSO numero di choices
       (stessa semantica): se il backend SWI-Prolog non e' attivo, la
       prolog-`la` ricade su gc_noheur e diverge da native-`la`
       -> ERRORE (cattura il bug di LAZY_HEURISTIC_BACKEND non esportato).
   Le altre varianti lazy che non riducono le choices (p.es. `lc` su BSP,
   per la semantica clingo) producono solo un WARNING, non un errore.

3) PUP, istanza piccola -> controllo leggero (l'enumerazione esaustiva e'
   intrattabile: double-20 ha ~9*10^5 modelli). Verifica che tutte le
   varianti/ backend concordino su SAT/UNSAT, riporta le choices e applica
   gli stessi guard di guida/wiring del punto (2).

4) HRP (House Reconfiguration Problem, Romero 1 Sez. 6.2) -> EQUIVALENZA
   ESAUSTIVA su istanza piccola (house-sanity), proiettando su
   cabinetTOthing/roomTOcabinet, piu' la guida misurata su un'istanza piu'
   grande (su quella minima il baseline risolve gia' con pochissime choices).
   HRP non ha aggregati: l'asse interessante e' il 'not' su assegnamento
   parziale (alpha vs clingo), quindi i guard del punto (2) restano validi.

Uso
---
  python3 tools/check_equivalence.py                 # native + prolog
  python3 tools/check_equivalence.py --backends native
  python3 tools/check_equivalence.py --bsp-n 8 --pup-instance .../double-20.asp
  python3 tools/check_equivalence.py --strict-guidance   # WARNING -> ERRORE

Exit code: 0 = tutto ok (eventuali warning), 1 = violazione di correttezza.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
TEST_ROOT = TOOLS_DIR.parents[1]   # test_folder (encodings-*/instances vivono qui, sopra benchmark_folder_clingo)
REPO_ROOT = TEST_ROOT.parent

SUCCESS_RETURN_CODES = {0, 10, 20, 30}
GREEN, RED, YELLOW, BOLD, RESET = "\033[32m", "\033[31m", "\033[33m", "\033[1m", "\033[0m"


def color(text: str, code: str) -> str:
    if not sys.stdout.isatty() or os.environ.get("NO_COLOR"):
        return text
    return f"{code}{text}{RESET}"


def clingo_bin(backend: str) -> Path:
    override = os.environ.get("CLINGO_BIN")
    if override:
        return Path(override)
    return REPO_ROOT / f"clingo-{backend}" / "build" / "bin" / "clingo"


def backend_env(backend: str) -> dict[str, str]:
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    env["LC_NUMERIC"] = "C"
    # Correzione critica: il backend prolog usa SWI-Prolog solo con questa var.
    if backend == "prolog":
        env["LAZY_HEURISTIC_BACKEND"] = "prolog"
    else:
        env.pop("LAZY_HEURISTIC_BACKEND", None)
    # Abilita il summary su stderr ("[lazy-prolog] summary decide_calls=...") cosi'
    # da poter verificare che il propagatore prolog sia DAVVERO entrato in azione.
    env["LAZY_PROLOG_STATS"] = "1"
    return env


def parse_decide_calls(stderr: str) -> int | None:
    # Estrae decide_calls dal summary del backend prolog. None se il summary non
    # e' stato emesso (il propagatore non e' mai entrato in azione: fallback).
    for line in stderr.splitlines():
        stripped = line.strip()
        if not stripped.startswith("[lazy-prolog] summary"):
            continue
        for part in stripped.split():
            if part.startswith("decide_calls="):
                try:
                    return int(part.split("=", 1)[1])
                except ValueError:
                    return None
    return None


class ClingoResult:
    __slots__ = ("result", "witnesses", "choices", "decides", "ok")

    def __init__(self, result, witnesses, choices, ok, decides=None):
        self.result = result
        self.witnesses = witnesses  # set[frozenset[str]] | None
        self.choices = choices      # int | None
        self.decides = decides      # int | None  (decide_calls del backend prolog)
        self.ok = ok


def run_clingo(backend, files, *, consts=None, n_models=1, seed=0,
               project=False, timeout=60) -> ClingoResult:
    cmd = [str(clingo_bin(backend)), *[str(f) for f in files]]
    for const in consts or []:
        cmd += ["-c", const]
    cmd += ["--heuristic=Domain", "--outf=2", "--stats=2",
            "-n", str(n_models), f"--seed={seed}", f"--time-limit={timeout}"]
    if project:
        cmd.append("--project")
    try:
        proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=timeout + 10,
                              env=backend_env(backend))
    except subprocess.TimeoutExpired:
        return ClingoResult("TIMEOUT", None, None, False)

    if proc.returncode not in SUCCESS_RETURN_CODES:
        return ClingoResult(f"EXIT_{proc.returncode}", None, None, False)
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return ClingoResult("BADJSON", None, None, False)

    result = data.get("Result", "UNKNOWN")
    choices = _nested(data, ["Stats", "Core", "Choices"])
    choices = int(choices) if isinstance(choices, (int, float)) else None

    witnesses: set[frozenset[str]] | None = set()
    for call in data.get("Call", []):
        for witness in call.get("Witnesses", []):
            value = witness.get("Value")
            if value is None:
                witnesses = None
                break
            witnesses.add(frozenset(value))
        if witnesses is None:
            break
    decides = parse_decide_calls(proc.stderr)
    return ClingoResult(result, witnesses, choices, True, decides=decides)


def _nested(data, path, default=None):
    cur = data
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def _atom_predicate(atom: str) -> str:
    head = atom.split("(", 1)[0]
    return head[1:] if head.startswith("-") else head


def project(witnesses, predicates):
    """Proietta ogni answer set sui soli predicati-soluzione.

    Necessario perche' gli encoding hanno #show diversi (gc/ga mostrano anche
    x/1 e sum_value/1, gli encoding lazy no): confrontare i witness grezzi
    darebbe falsi positivi. La soluzione e' identificata dai soli predicati
    elencati (per BSP la partizione b/1, c/1)."""
    if witnesses is None:
        return None
    preds = set(predicates)
    return {
        frozenset(a for a in w if _atom_predicate(a) in preds)
        for w in witnesses
    }


class Report:
    def __init__(self, strict_guidance: bool):
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.strict_guidance = strict_guidance

    def error(self, msg: str):
        self.errors.append(msg)
        print(color(f"  [FAIL] {msg}", RED))

    def warn(self, msg: str):
        self.warnings.append(msg)
        print(color(f"  [WARN] {msg}", YELLOW))

    def ok(self, msg: str):
        print(color(f"  [ OK ] {msg}", GREEN))

    def guidance_problem(self, msg: str):
        # In modalita' strict, una mancata guida e' un errore; altrimenti warn.
        (self.error if self.strict_guidance else self.warn)(msg)


# --------------------------------------------------------------------------
# BSP: equivalenza esaustiva + guida
# --------------------------------------------------------------------------
def check_bsp(backends, variants, n, report: Report, solution_preds):
    print(color(f"\n=== BSP (n={n}) — equivalenza esaustiva degli answer set ===", BOLD))
    print(f"  Predicati-soluzione confrontati: {', '.join(sorted(solution_preds))}/1")
    enc = {b: TEST_ROOT / f"encodings-{b}" / "1_BSP" for b in backends}
    rng = TEST_ROOT / "instances" / "BSP_instances" / "BSP_range.lp"

    # (backend, variant) -> collezione di answer set (proiettati) ; choices ; decide_calls
    witness_sets: dict[tuple[str, str], set] = {}
    choices: dict[tuple[str, str], int | None] = {}
    decides: dict[tuple[str, str], int | None] = {}

    for backend in backends:
        for v in variants:
            f = enc[backend] / f"BSP_{v}.lp"
            if not f.is_file():
                report.warn(f"{backend}/BSP_{v}.lp assente, salto.")
                continue
            enum = run_clingo(backend, [rng, f], consts=[f"n={n}"], n_models=0)
            if not enum.ok or enum.witnesses is None:
                report.error(f"{backend}/BSP_{v}: enumerazione fallita ({enum.result}).")
                continue
            witness_sets[(backend, v)] = project(enum.witnesses, solution_preds)
            solve = run_clingo(backend, [rng, f], consts=[f"n={n}"], n_models=1)
            choices[(backend, v)] = solve.choices
            decides[(backend, v)] = solve.decides

    if not witness_sets:
        report.error("BSP: nessun risultato raccolto.")
        return

    # (1) tutte le collezioni di answer set devono coincidere.
    reference_key = next(iter(witness_sets))
    reference = witness_sets[reference_key]
    print(color(f"\n  Riferimento: {reference_key[0]}/{reference_key[1]} "
                f"-> {len(reference)} answer set", BOLD))
    all_equal = True
    for key, wset in witness_sets.items():
        if wset == reference:
            report.ok(f"{key[0]}/{key[1]}: {len(wset)} answer set, identici al riferimento.")
        else:
            all_equal = False
            only_ref = len(reference - wset)
            only_here = len(wset - reference)
            report.error(
                f"{key[0]}/{key[1]}: collezione DIVERSA "
                f"({len(wset)} answer set; +{only_here}/-{only_ref} vs riferimento)."
            )
    if all_equal:
        report.ok("Tutte le varianti/backend producono lo STESSO insieme di soluzioni.")

    _check_guidance(backends, variants, choices, decides, report, problem="BSP")


# --------------------------------------------------------------------------
# PUP: controllo leggero (SAT-consistency) + guida
# --------------------------------------------------------------------------
def check_pup(backends, variants, instance: Path, report: Report):
    print(color(f"\n=== PUP ({instance.name}) — consistenza SAT + guida ===", BOLD))
    print(color("  (enumerazione esaustiva omessa: lo spazio dei modelli e' troppo grande)", YELLOW))
    enc = {b: TEST_ROOT / f"encodings-{b}" / "2_PUP" for b in backends}

    results: dict[tuple[str, str], str] = {}
    choices: dict[tuple[str, str], int | None] = {}
    decides: dict[tuple[str, str], int | None] = {}
    for backend in backends:
        for v in variants:
            f = enc[backend] / f"PUP_{v}.lp"
            if not f.is_file():
                report.warn(f"{backend}/PUP_{v}.lp assente, salto.")
                continue
            solve = run_clingo(backend, [f, instance], n_models=1)
            results[(backend, v)] = solve.result
            choices[(backend, v)] = solve.choices
            decides[(backend, v)] = solve.decides

    if not results:
        report.error("PUP: nessun risultato raccolto.")
        return

    distinct = set(results.values())
    if distinct <= {"SATISFIABLE"} or distinct <= {"UNSATISFIABLE"}:
        report.ok(f"Tutte le varianti/backend concordano: {next(iter(distinct))}.")
    else:
        report.error(f"Discordanza SAT/UNSAT tra varianti/backend: {results}.")

    _check_guidance(backends, variants, choices, decides, report, problem="PUP")


# --------------------------------------------------------------------------
# HRP: equivalenza esaustiva (istanza piccola) + guida (istanza piu' grande)
# --------------------------------------------------------------------------
def check_hrp(backends, variants, instance: Path, guidance_instance: Path,
              report: Report, solution_preds):
    print(color(f"\n=== HRP ({instance.name}) — equivalenza esaustiva degli answer set ===", BOLD))
    print(f"  Predicati-soluzione confrontati: {', '.join(sorted(solution_preds))}")
    enc = {b: TEST_ROOT / f"encodings-{b}" / "3_HRP" for b in backends}

    witness_sets: dict[tuple[str, str], set] = {}
    for backend in backends:
        for v in variants:
            f = enc[backend] / f"HRP_{v}.lp"
            if not f.is_file():
                report.warn(f"{backend}/HRP_{v}.lp assente, salto.")
                continue
            enum = run_clingo(backend, [instance, f], n_models=0, project=True)
            if not enum.ok or enum.witnesses is None:
                report.error(f"{backend}/HRP_{v}: enumerazione fallita ({enum.result}).")
                continue
            witness_sets[(backend, v)] = project(enum.witnesses, solution_preds)

    if not witness_sets:
        report.error("HRP: nessun risultato raccolto.")
        return

    reference_key = next(iter(witness_sets))
    reference = witness_sets[reference_key]
    print(color(f"\n  Riferimento: {reference_key[0]}/{reference_key[1]} "
                f"-> {len(reference)} answer set", BOLD))
    all_equal = True
    for key, wset in witness_sets.items():
        if wset == reference:
            report.ok(f"{key[0]}/{key[1]}: {len(wset)} answer set, identici al riferimento.")
        else:
            all_equal = False
            only_ref = len(reference - wset)
            only_here = len(wset - reference)
            report.error(
                f"{key[0]}/{key[1]}: collezione DIVERSA "
                f"({len(wset)} answer set; +{only_here}/-{only_ref} vs riferimento)."
            )
    if all_equal:
        report.ok("Tutte le varianti/backend producono lo STESSO insieme di soluzioni.")

    # La guida si misura su un'istanza non banale (su quella minima di
    # equivalenza il baseline risolve gia' con pochissime choices).
    print(color(f"\n  (guida HRP misurata su istanza piu' grande: {guidance_instance.name})", YELLOW))
    choices: dict[tuple[str, str], int | None] = {}
    decides: dict[tuple[str, str], int | None] = {}
    for backend in backends:
        for v in variants:
            f = enc[backend] / f"HRP_{v}.lp"
            if not f.is_file():
                continue
            solve = run_clingo(backend, [guidance_instance, f], n_models=1, timeout=120)
            choices[(backend, v)] = solve.choices
            decides[(backend, v)] = solve.decides

    _check_guidance(backends, variants, choices, decides, report, problem="HRP")


# --------------------------------------------------------------------------
# Guida della ricerca + wiring del backend prolog
# --------------------------------------------------------------------------
def _check_guidance(backends, variants, choices, decides, report: Report, *, problem: str):
    print(color(f"\n  --- {problem}: guida della ricerca (choices, seed=0) ---", BOLD))
    for backend in backends:
        line = "  ".join(
            f"{v}={choices.get((backend, v))}"
            for v in variants if (backend, v) in choices
        )
        print(f"    {backend:7s} | {line}")

    # (0) Attivita' dell'euristica lazy sul backend prolog: decide_calls > 0.
    # E' la prova DIRETTA che il propagatore SWI-Prolog e' entrato in azione.
    # decide_calls assente/0 = fallback silenzioso al backend ausiliario
    # (la ricerca gira senza euristica). Sul backend native decide_calls NON e'
    # instrumentato (None): in quel caso la guida e' verificata indirettamente
    # dal calo di choices (controllo 2a).
    if "prolog" in backends:
        print(color(f"\n  --- {problem}: attivita' euristica lazy (decide_calls, backend prolog) ---", BOLD))
        line = "  ".join(
            f"{v}={decides.get(('prolog', v))}"
            for v in variants if ('prolog', v) in decides
        )
        print(f"    prolog  | {line}")
        for v in variants:
            if not v.lower().startswith("l"):
                continue  # solo le varianti lazy attivano il propagatore
            if ("prolog", v) not in decides:
                continue
            dc = decides.get(("prolog", v))
            if dc is None or dc == 0:
                report.error(
                    f"prolog/{v}: decide_calls={dc} -> il propagatore SWI-Prolog "
                    f"NON e' entrato in azione (fallback silenzioso al backend "
                    f"ausiliario? manca LAZY_HEURISTIC_BACKEND=prolog?). "
                    f"Il run coincide con gc_noheur e NON misura l'euristica."
                )
            else:
                report.ok(f"prolog/{v}: decide_calls={dc} > 0 (propagatore attivo).")

    # (2a) la flagship `la` deve guidare: meno choices del baseline gc_noheur.
    for backend in backends:
        base = choices.get((backend, "gc_noheur"))
        la = choices.get((backend, "la"))
        if base is None or la is None:
            continue
        if la < base:
            report.ok(f"{backend}/la guida: {la} choices < gc_noheur {base}.")
        else:
            report.guidance_problem(
                f"{backend}/la NON guida: {la} choices >= gc_noheur {base} "
                f"(euristica lazy inattiva?)."
            )

    # (2b) wiring prolog: native-la e prolog-la devono fare le STESSE choices.
    if "native" in backends and "prolog" in backends:
        nat = choices.get(("native", "la"))
        pro = choices.get(("prolog", "la"))
        if nat is not None and pro is not None:
            if nat == pro:
                report.ok(f"native-la e prolog-la concordano: {nat} choices "
                          f"(backend SWI-Prolog attivo).")
            else:
                report.error(
                    f"native-la={nat} != prolog-la={pro}: il backend SWI-Prolog "
                    f"sembra NON attivo (manca LAZY_HEURISTIC_BACKEND=prolog?)."
                )

    # (2c) segnala (warning) altre varianti lazy che non riducono le choices.
    for backend in backends:
        base = choices.get((backend, "gc_noheur"))
        if base is None:
            continue
        for v in variants:
            if v in ("la", "gc_noheur") or not v.startswith("l"):
                continue
            c = choices.get((backend, v))
            if c is not None and c >= base:
                report.warn(
                    f"{backend}/{v}: {c} choices >= gc_noheur {base} "
                    f"(nessuna riduzione; atteso per la semantica clingo)."
                )


def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--backends", nargs="+", default=["native", "prolog"],
                   choices=["native", "prolog"],
                   help="Backend da verificare. Default: native prolog.")
    p.add_argument("--bsp-variants", nargs="+",
                   default=["gc_noheur", "gc", "ga", "la", "lc"],
                   help="Varianti BSP da confrontare.")
    p.add_argument("--pup-variants", nargs="+",
                   default=["gc_noheur", "gc", "ga", "la", "lc"],
                   help="Varianti PUP da confrontare.")
    p.add_argument("--bsp-n", type=int, default=6,
                   help="Costante n per il test esaustivo BSP. Default: 6.")
    p.add_argument("--bsp-solution-preds", nargs="+", default=["b", "c"],
                   help="Predicati che identificano la soluzione BSP. Default: b c.")
    p.add_argument("--pup-instance",
                   default=str(TEST_ROOT / "instances" / "PUP_instances" /
                               "Double" / "double-20.asp"),
                   help="Istanza PUP per il controllo leggero.")
    p.add_argument("--hrp-variants", nargs="+",
                   default=["gc_noheur", "gc", "ga", "la", "lc"],
                   help="Varianti HRP da confrontare.")
    p.add_argument("--hrp-instance",
                   default=str(TEST_ROOT / "instances" / "HRP_instances" /
                               "house-sanity.asp"),
                   help="Istanza HRP piccola per l'equivalenza esaustiva.")
    p.add_argument("--hrp-guidance-instance",
                   default=str(TEST_ROOT / "instances" / "HRP_instances" /
                               "house-10.asp"),
                   help="Istanza HRP piu' grande su cui misurare la guida.")
    p.add_argument("--hrp-solution-preds", nargs="+",
                   default=["cabinetTOthing", "roomTOcabinet"],
                   help="Predicati che identificano la soluzione HRP.")
    p.add_argument("--skip-bsp", action="store_true")
    p.add_argument("--skip-pup", action="store_true")
    p.add_argument("--skip-hrp", action="store_true")
    p.add_argument("--strict-guidance", action="store_true",
                   help="Tratta i problemi di guida come errori, non warning.")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    for backend in args.backends:
        cb = clingo_bin(backend)
        if not (cb.is_file() and os.access(cb, os.X_OK)):
            print(color(f"Errore: binario clingo {backend} non trovato: {cb}", RED))
            return 2

    report = Report(strict_guidance=args.strict_guidance)
    if not args.skip_bsp:
        check_bsp(args.backends, args.bsp_variants, args.bsp_n, report,
                  set(args.bsp_solution_preds))
    if not args.skip_pup:
        instance = Path(args.pup_instance)
        if instance.is_file():
            check_pup(args.backends, args.pup_variants, instance, report)
        else:
            report.warn(f"Istanza PUP non trovata, salto PUP: {instance}")
    if not args.skip_hrp:
        hrp_inst = Path(args.hrp_instance)
        hrp_guid = Path(args.hrp_guidance_instance)
        if not hrp_guid.is_file():
            hrp_guid = hrp_inst  # fallback: usa la stessa istanza piccola
        if hrp_inst.is_file():
            check_hrp(args.backends, args.hrp_variants, hrp_inst, hrp_guid,
                      report, set(args.hrp_solution_preds))
        else:
            report.warn(f"Istanza HRP non trovata, salto HRP: {hrp_inst}")

    print(color("\n=== Riepilogo ===", BOLD))
    print(f"  Errori:  {len(report.errors)}")
    print(f"  Warning: {len(report.warnings)}")
    if report.errors:
        print(color("  RISULTATO: FALLITO (violazione di correttezza).", RED))
        return 1
    print(color("  RISULTATO: OK.", GREEN))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
