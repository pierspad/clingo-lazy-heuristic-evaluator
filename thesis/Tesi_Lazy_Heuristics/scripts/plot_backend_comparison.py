"""Regenerate the thesis la backend comparison from the recorded HPC campaign."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

THESIS = Path(__file__).resolve().parents[1]
ROOT = THESIS.parents[1]
SOURCE = ROOT / 'clingo_hpc_graphs/results.xml'
OUTPUT = THESIS / 'figures/hpc/backend_la_comparison.pdf'

def read_runs():
    root = ET.parse(SOURCE).getroot()
    names = {(b.get('name'), c.get('id'), i.get('id')): i.get('name')
             for b in root.findall('benchmark') for c in b.findall('class')
             for i in c.findall('instance')}
    result = {}
    for project in root.findall('project'):
        for spec in project.findall('runspec'):
            if spec.get('setting') not in ('la', 'lc', 'gc') or spec.get('system') not in ('clingo-native', 'clingo-prolog'):
                continue
            family, system = spec.get('benchmark'), spec.get('system')
            for cls in spec.findall('class'):
                for inst in cls.findall('instance'):
                    name = names[(family, cls.get('id'), inst.get('id'))]
                    size = int(re.search(r'(\d+)$', name).group())
                    for run in inst.findall('run'):
                        values = {m.get('name'): m.get('val') for m in run.findall('measure')}
                        if values.get('status') != 'SATISFIABLE' or any(float(values.get(k, 0)) for k in ('timeout', 'memout', 'error')):
                            continue
                        result.setdefault((family, system, spec.get('setting')), []).append((size, float(values['clingo_total']), float(values['solving'])))
    return {key: sorted(values) for key, values in result.items()}

def main():
    runs = read_runs()
    plt.rcParams.update({'font.size': 11, 'axes.titlesize': 12, 'axes.labelsize': 10.5,
                         'xtick.labelsize': 10, 'ytick.labelsize': 10, 'pdf.fonttype': 42})
    fig, axes = plt.subplots(3, 2, figsize=(7.2, 8.8), layout='constrained')
    styles = [('clingo-native', 'C++', '#0072B2', 'o', '-'),
              ('clingo-prolog', 'Prolog', '#D55E00', 's', '--')]
    for row, family in enumerate(('BSP', 'PUP', 'HRP')):
        for col, metric in enumerate(('Total time', 'Solving time')):
            ax = axes[row, col]
            for system, label, color, marker, line in styles:
                points = runs[(family, system, 'la')]
                ax.plot([p[0] for p in points], [max(p[col+1], .005) if col else p[col+1] for p in points],
                        color=color, marker=marker, markersize=3.5, linewidth=1.4,
                        linestyle=line, label=label)
            ax.set_title(f'{family} — {metric}')
            ax.set_xlabel('Instance size ' + ('n' if family == 'BSP' else 'N'))
            ax.set_ylabel('Time (s)')
            ax.grid(True, alpha=.22)
            ax.spines[['top', 'right']].set_visible(False)
            if col:
                ax.set_yscale('log')
                ax.set_ylim(bottom=.0038)
                ax.set_yticks([.005, .01, .1, 1, 10] if family != 'BSP' else [.005, .01, .1, 1])
                ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: '<0.01' if v == .005 else f'{v:g}'))
                ax.set_ylim(top=max(max(p[2] for system,*_ in styles for p in runs[(family,system, 'la')])*1.8, .15))
            else:
                ax.set_ylim(bottom=0)
            if row == 0 and col == 0:
                ax.legend(frameon=False, loc='upper left')
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUTPUT, metadata={'Title': 'Lazy Alpha-like heuristics: C++ versus Prolog',
                                 'Subject': 'Successful runs from clingo_hpc_graphs/results.xml'})
    plt.close(fig)
    from matplotlib.lines import Line2D
    fig, axes = plt.subplots(3, 1, figsize=(7.2, 8.8), layout='constrained')
    colors = {'la': '#0072B2', 'lc': '#AA4499', 'gc': '#666666'}
    for ax, family in zip(axes, ('BSP', 'PUP', 'HRP')):
        for variant, color in colors.items():
            for system, _, _, marker, line in styles:
                points = runs[(family, system, variant)]
                # Keep a failed intermediate instance as a gap (notably PUP lc at N=80).
                step, end = {'BSP': (10, 200), 'PUP': (20, 200), 'HRP': (2, 20)}[family]
                by_size = {point[0]: point[2] for point in points}
                sizes = list(range(step, end + 1, step))
                values = [max(by_size[n], .005) if n in by_size else float('nan') for n in sizes]
                ax.plot(sizes, values,
                        color=color, linestyle=line, marker=marker,
                        markersize=3.5, linewidth=1.4)
        ax.set_title(f'{family} — Solving time')
        ax.set_xlabel('Instance size ' + ('n' if family == 'BSP' else 'N'))
        ax.set_ylabel('Time (s), log scale')
        ax.set_yscale('log')
        ax.set_ylim(.0035, 1000)
        ax.set_yticks([.005, .1, 1, 10, 100, 600])
        ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: '<0.01' if v == .005 else f'{v:g}'))
        ax.axhline(600, color='#999999', linewidth=.6, linestyle=':')
        ax.grid(True, alpha=.22)
        ax.spines[['top', 'right']].set_visible(False)
    handles = [Line2D([], [], color=color, label=variant) for variant, color in colors.items()]
    handles += [Line2D([], [], color='black', linestyle=line, marker=marker, label=label)
                for _, label, _, marker, line in styles]
    fig.legend(handles=handles, loc='outside upper center', ncol=5, frameon=False)
    fig.savefig(OUTPUT.with_name('backend_semantics_comparison.pdf'))
    plt.close(fig)

if __name__ == '__main__':
    main()
