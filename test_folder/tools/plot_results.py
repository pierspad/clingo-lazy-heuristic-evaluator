#!/usr/bin/env python3
"""Grafici dai risultati di benchmark-tool.

Sorgente: il file XML prodotto da
    btool eval runscripts/runscript.xml > results.xml
(contiene TUTTE le misure del resultparser custom, a differenza del parquet
esportato da conv che ne include solo un sottoinsieme). Lo trasformiamo in
formato tidy e produciamo, per ogni famiglia (BSP/PUP/HRP):

  * tempo di solving vs taglia
  * memoria di picco (mem) vs taglia      <-- metrica centrale della tesi
  * (se presenti) decide_calls vs taglia  <-- attivita' del propagatore lazy

Una curva per ogni coppia (system, setting). I run andati in timeout/errore
sono esclusi dalle curve di tempo/memoria (status non risolto).

Uso:
    python3 tools/plot_results.py                          # machine=local
    python3 tools/plot_results.py --machine hpc
    python3 tools/plot_results.py --results results.xml --out graphs
    python3 tools/plot_results.py --measures solving mem decide_calls
"""
from __future__ import annotations

import argparse
import re
import xml.etree.ElementTree as ET
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402

# nome istanza -> (famiglia, taglia)
INSTANCE_RE = re.compile(r"^(?P<fam>bsp|double|house)-(?P<size>\d+)", re.IGNORECASE)
FAMILY = {"bsp": "BSP", "double": "PUP", "house": "HRP"}


def load_tidy(results_xml: Path) -> pd.DataFrame:
    """Parsa il results.xml di benchmark-tool in formato tidy (long).

    Struttura: <benchmark> definisce class/instance (id -> name); <project>/
    <runspec> (machine, system, setting, benchmark) -> class/instance/run/
    measure. Risolviamo gli id istanza tramite la mappa del benchmark.
    """
    root = ET.parse(results_xml).getroot()

    # benchmark name -> {class_id -> {instance_id -> instance_name}}
    bench: dict[str, dict[str, dict[str, str]]] = {}
    for b in root.findall("benchmark"):
        bname = b.get("name")
        cmap: dict[str, dict[str, str]] = {}
        for cls in b.findall("class"):
            imap = {inst.get("id"): inst.get("name") for inst in cls.findall("instance")}
            cmap[cls.get("id")] = imap
        bench[bname] = cmap

    records = []
    for project in root.findall("project"):
        for rs in project.findall("runspec"):
            machine = rs.get("machine")
            system = rs.get("system")
            setting = rs.get("setting")
            bname = rs.get("benchmark")
            cmap = bench.get(bname, {})
            for cls in rs.findall("class"):
                imap = cmap.get(cls.get("id"), {})
                for inst in cls.findall("instance"):
                    iname = imap.get(inst.get("id"), inst.get("id"))
                    for run in inst.findall("run"):
                        for m in run.findall("measure"):
                            records.append(
                                {
                                    "instance": iname,
                                    "measure": m.get("name"),
                                    "system": system,
                                    "setting": setting,
                                    "machine": machine,
                                    "value": m.get("val"),
                                }
                            )
    tidy = pd.DataFrame.from_records(records)

    fam, size = [], []
    for name in tidy["instance"]:
        m = INSTANCE_RE.match(str(name))
        if m:
            fam.append(FAMILY[m.group("fam").lower()])
            size.append(int(m.group("size")))
        else:
            fam.append("?")
            size.append(-1)
    tidy["family"] = fam
    tidy["size"] = size
    return tidy


def solved_mask(tidy: pd.DataFrame) -> pd.Series:
    """True per le istanze risolte (timeout==0 e error==0)."""
    wide = tidy.pivot_table(
        index=["instance", "system", "setting", "machine"],
        columns="measure",
        values="value",
        aggfunc="first",
    )
    ok = pd.Series(True, index=wide.index)
    for flag in ("timeout", "error", "memout"):
        if flag in wide.columns:
            ok &= wide[flag].fillna(1).astype(float) == 0
    return ok


def plot_measure(tidy: pd.DataFrame, measure: str, machine: str, out_dir: Path) -> None:
    sub = tidy[(tidy["measure"] == measure) & (tidy["machine"] == machine)].copy()
    if sub.empty:
        print(f"  (nessun dato per measure={measure} machine={machine})")
        return

    ok = solved_mask(tidy)
    sub = sub.set_index(["instance", "system", "setting", "machine"])
    sub = sub[ok.reindex(sub.index).fillna(False)]
    sub = sub.reset_index()
    sub["value"] = pd.to_numeric(sub["value"], errors="coerce")
    sub = sub.dropna(subset=["value"])
    if sub.empty:
        print(f"  (solo run non risolti per measure={measure} machine={machine})")
        return

    for family, fam_df in sub.groupby("family"):
        if family == "?":
            continue
        fig, ax = plt.subplots(figsize=(9, 6))
        for (system, setting), grp in fam_df.groupby(["system", "setting"]):
            grp = grp.sort_values("size")
            agg = grp.groupby("size")["value"].median()
            label = f"{system.replace('clingo-','').replace('-1.0','')}/{setting}"
            ax.plot(agg.index, agg.values, marker="o", markersize=3, linewidth=1.2, label=label)
        ax.set_xlabel("taglia istanza (n)")
        ax.set_ylabel(measure)
        ax.set_title(f"{family} — {measure} ({machine})")
        ax.grid(True, alpha=0.3)
        ax.legend(fontsize=7, ncol=2)
        out = out_dir / f"{family}_{measure}_{machine}.png"
        fig.tight_layout()
        fig.savefig(out, dpi=120)
        plt.close(fig)
        print(f"  scritto {out}")


def main() -> None:
    here = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description="Grafici dai risultati benchmark-tool.")
    ap.add_argument("--results", type=Path, default=here / "results.xml")
    ap.add_argument("--machine", default="local")
    ap.add_argument("--measures", nargs="+", default=["solving", "mem", "decide_calls"])
    ap.add_argument("--out", type=Path, default=here / "graphs")
    args = ap.parse_args()

    if not args.results.exists():
        raise SystemExit(
            f"results.xml non trovato: {args.results}\n"
            "Genera prima i risultati:\n"
            "  btool eval runscripts/runscript.xml > results.xml"
        )

    tidy = load_tidy(args.results)
    args.out.mkdir(parents=True, exist_ok=True)
    print(f"Istanze: {tidy['instance'].nunique()}  config: "
          f"{tidy[['system','setting']].drop_duplicates().shape[0]}  machine={args.machine}")
    for measure in args.measures:
        print(f"measure: {measure}")
        plot_measure(tidy, measure, args.machine, args.out)


if __name__ == "__main__":
    main()
