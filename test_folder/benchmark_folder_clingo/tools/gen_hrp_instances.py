#!/usr/bin/env python3
"""
Generatore di istanze HRP (House Reconfiguration Problem) scalabili.
================================================================
Produce file ``house-<N>.asp`` (famiglia parametrica per dimensione, come
``double-*.asp`` per PUP) nello schema atteso dagli encoding ``3_HRP``:

  person/1, thing/1, personTOthing/2, thingLong/1,
  cabinetDomainNew/1, roomDomainNew/1,
  e (opzionale, riconfigurazione) legacyCabinet/1, legacyRoom/1,
  legacyCabinetThing/2, legacyRoomCabinet/2.

Costruzione (SAT per costruzione):
  - N persone, ognuna possiede ``--things-per-person`` cose (default 4, <=5
    cosi' stanno tutte in UN cabinet senza violare il limite di 5);
  - ogni k-esima cosa e' "long" (cabinet alto, 2 slot) -> il cabinet della
    persona resta valido (1 cabinet alto = 2 slot <= 4 per stanza);
  - dominio: N+slack cabinet e N+slack stanze (slack -> liberta' di scelta,
    quindi l'euristica conta davvero);
  - soluzione canonica: persona i -> cabinet i -> stanza i.
  - ``--legacy-fraction`` f: le prime ceil(f*N) persone hanno la loro
    assegnazione canonica marcata come legacy (riconfigurazione: riusabile,
    quindi l'istanza resta SAT e le euristiche di reuse @4 si attivano).

Esempi:
  python3 gen_hrp_instances.py --sizes 4 6 8 10 --out ../instances/HRP_instances
  python3 gen_hrp_instances.py --sizes 20 --legacy-fraction 0.5
"""
from __future__ import annotations

import argparse
import math
import os
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
TEST_ROOT = TOOLS_DIR.parents[1]   # test_folder (instances/ vive un livello sopra benchmark_folder_clingo)
DEFAULT_OUT = TEST_ROOT / "instances" / "HRP_instances"


def gen_instance(n_persons: int, tpp: int, long_every: int,
                 slack: int, legacy_fraction: float) -> str:
    lines: list[str] = []
    lines.append(f"% HRP instance generato automaticamente (gen_hrp_instances.py)")
    lines.append(f"% persone={n_persons} cose/persona={tpp} slack={slack} "
                 f"legacy_fraction={legacy_fraction}")
    lines.append("")

    n_things = n_persons * tpp
    n_cab = n_persons + slack
    n_room = n_persons + slack

    # persone e cose: la persona p possiede le cose (p-1)*tpp+1 .. p*tpp
    persons = list(range(1, n_persons + 1))
    lines.append("% --- persone, cose, possesso ---")
    lines.append("person(1.." + str(n_persons) + ").")
    lines.append("thing(1.." + str(n_things) + ").")
    owner_of = {}
    for p in persons:
        first = (p - 1) * tpp + 1
        last = p * tpp
        owner_of.update({t: p for t in range(first, last + 1)})
        lines.append(f"personTOthing({p},{first}..{last}).")
    lines.append("")

    # cose lunghe: ogni long_every-esima
    longs = [t for t in range(1, n_things + 1) if long_every > 0 and t % long_every == 0]
    lines.append("% --- cose lunghe (cabinet alto) ---")
    if longs:
        lines.append(" ".join(f"thingLong({t})." for t in longs))
    else:
        lines.append("% (nessuna cosa lunga)")
    lines.append("")

    # domini
    lines.append("% --- dominio cabinet/stanze (con slack) ---")
    lines.append(f"cabinetDomainNew(1..{n_cab}).")
    lines.append(f"roomDomainNew(1..{n_room}).")
    lines.append("")

    # legacy (riconfigurazione): prime ceil(f*N) persone assegnate canonicamente
    n_legacy = math.ceil(legacy_fraction * n_persons)
    lines.append("% --- legacy configuration (riconfigurazione) ---")
    if n_legacy <= 0:
        lines.append("% (legacy vuoto: configurazione pura)")
    else:
        for p in range(1, n_legacy + 1):
            first = (p - 1) * tpp + 1
            last = p * tpp
            lines.append(f"legacyCabinet({p}). legacyRoom({p}). "
                         f"legacyRoomCabinet({p},{p}).")
            lines.append(f"legacyCabinetThing({p},{first}..{last}).")
    lines.append("")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sizes", type=int, nargs="+",
                    default=[4, 6, 8, 10, 12, 14, 16, 18, 20],
                    help="Numero di persone per ciascuna istanza (knob di dimensione).")
    ap.add_argument("--things-per-person", type=int, default=4)
    ap.add_argument("--long-every", type=int, default=4,
                    help="Una cosa ogni N e' lunga (0 = nessuna).")
    ap.add_argument("--slack", type=int, default=2,
                    help="Cabinet/stanze extra oltre il minimo (liberta' di scelta).")
    ap.add_argument("--legacy-fraction", type=float, default=0.5,
                    help="Frazione di persone con assegnazione legacy (riuso).")
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    args = ap.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    for n in args.sizes:
        text = gen_instance(n, args.things_per_person, args.long_every,
                            args.slack, args.legacy_fraction)
        path = out_dir / f"house-{n}.asp"
        path.write_text(text, encoding="utf-8")
        print(f"  scritto {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
