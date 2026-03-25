import os
import re
import shutil
import subprocess
import time

# Configurazioni
N_VALUES = range(10, 101, 5)  # Da N=10 a N=100 con step 10
CLINGO_STD = "clingo"
CLINGO_MOD = "/home/ribben/Desktop/clingo-lazy-heuristics/clingo-modified/build/bin/clingo"
FILE_STD = "__BSP.lp"
FILE_MOD = "_2_non_ground.lp"
FILE_RANGE = "__.common_range.lp"
GRAPHS_DIR = "graphs"
CLINGO_OK_CODES = {0, 10, 20, 30}

TIME_BIN = shutil.which("time")


def parse_elapsed_to_seconds(elapsed_str):
    """Converte il formato elapsed di GNU time in secondi (h:mm:ss, m:ss, con frazioni)."""
    raw = elapsed_str.strip()
    parts = raw.split(":")

    try:
        if len(parts) == 3:
            hours = int(parts[0])
            minutes = int(parts[1])
            seconds = float(parts[2])
            return hours * 3600 + minutes * 60 + seconds
        if len(parts) == 2:
            minutes = int(parts[0])
            seconds = float(parts[1])
            return minutes * 60 + seconds
        return float(raw)
    except ValueError:
        return None

# Dizionari per salvare i risultati
results = {
    "std": {"time": [], "memory": []},
    "mod": {"time": [], "memory": []}
}

def run_command(command):
    """Esegue un comando con time -v e ne estrae tempo e memoria (RSS)."""
    if TIME_BIN is None:
        print(
            "Avviso: comando GNU 'time' non trovato. "
            "Uso fallback interno (tempo + RSS da /proc)."
        )
        print(f"Eseguendo: {' '.join(command)}")
        return run_command_fallback_linux(command)

    # Usa time -v per profilare memoria e tempo
    full_cmd = [TIME_BIN, "-v"] + command

    print(f"Eseguendo: {' '.join(full_cmd)}")
    
    try:
        # Catturiamo sia stdout che stderr (time stampa le statistiche su stderr)
        process = subprocess.run(
            full_cmd,
            capture_output=True,
            text=True,
            check=False,
            env={**os.environ, "LC_ALL": "C"},
        )
        output = process.stderr  # time -v scrive qui

        if process.returncode not in CLINGO_OK_CODES:
            print(f"Comando terminato con codice inatteso {process.returncode}.")
        
        # Estraiamo l'RSS in kbytes
        mem_match = re.search(r"Maximum resident set size \(kbytes\):\s+(\d+)", output)
        # Tempo wall-clock (piu rappresentativo per benchmark end-to-end)
        elapsed_match = re.search(
            r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s+(.+)",
            output,
        )
        
        if mem_match and elapsed_match:
            memory_mb = int(mem_match.group(1)) / 1024.0  # Converti KB in MB
            time_sec = parse_elapsed_to_seconds(elapsed_match.group(1))
            if time_sec is None:
                print("Errore nel parsing del tempo elapsed.")
                return None, None
            return time_sec, memory_mb
        else:
            print("Errore nel parsing dell'output di time.")
            return None, None
            
    except Exception as e:
        print(f"Errore durante l'esecuzione: {e}")
        return None, None


def _read_proc_rss_kb(pid):
    """Legge la RSS corrente del processo da /proc/<pid>/status (kB)."""
    try:
        with open(f"/proc/{pid}/status", "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    # Formato tipico: "VmRSS:\t   1234 kB"
                    return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
        return None
    return None


def run_command_fallback_linux(command):
    """Fallback Linux senza GNU time: misura wall-time e picco RSS da /proc."""
    try:
        start = time.perf_counter()
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={**os.environ, "LC_ALL": "C"},
        )

        peak_rss_kb = 0
        while process.poll() is None:
            rss_kb = _read_proc_rss_kb(process.pid)
            if rss_kb is not None:
                peak_rss_kb = max(peak_rss_kb, rss_kb)
            time.sleep(0.02)

        # Ultima lettura prima di raccogliere output
        rss_kb = _read_proc_rss_kb(process.pid)
        if rss_kb is not None:
            peak_rss_kb = max(peak_rss_kb, rss_kb)

        _stdout, stderr = process.communicate()
        elapsed = time.perf_counter() - start

        if process.returncode not in CLINGO_OK_CODES:
            print(f"Comando terminato con codice inatteso {process.returncode}.")
            if stderr.strip():
                print(stderr.strip())

        memory_mb = (peak_rss_kb / 1024.0) if peak_rss_kb > 0 else None
        return elapsed, memory_mb

    except Exception as e:
        print(f"Errore durante il fallback: {e}")
        return None, None


def format_metric(time_val, mem_val):
    """Formatta metriche anche quando non disponibili."""
    time_str = f"{time_val:.4f} s" if time_val is not None else "N/D"
    mem_str = f"{mem_val:.2f} MB" if mem_val is not None else "N/D"
    return time_str, mem_str


def generate_graphs():
    """Genera i grafici in ./graphs/ se matplotlib e disponibile."""
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print(
            "Matplotlib non installato: benchmark completato senza grafici. "
            "Per abilitarli: pip install matplotlib"
        )
        return

    os.makedirs(GRAPHS_DIR, exist_ok=True)
    out_path = os.path.join(GRAPHS_DIR, "benchmark_results.png")

    plt.figure(figsize=(12, 5))

    # Grafico 1: Tempo
    plt.subplot(1, 2, 1)
    plt.plot(list(N_VALUES), results["std"]["time"], marker="o", label="Clingo Standard", color="red")
    plt.plot(list(N_VALUES), results["mod"]["time"], marker="s", label="Clingo Lazy (Modificato)", color="green")
    plt.title("Tempo di esecuzione")
    plt.xlabel("Dimensione del problema (N)")
    plt.ylabel("Tempo (Secondi)")
    plt.legend()
    plt.grid(True)

    # Grafico 2: Memoria
    plt.subplot(1, 2, 2)
    plt.plot(list(N_VALUES), results["std"]["memory"], marker="o", label="Clingo Standard", color="red")
    plt.plot(list(N_VALUES), results["mod"]["memory"], marker="s", label="Clingo Lazy (Modificato)", color="green")
    plt.title("Consumo di Memoria (RSS)")
    plt.xlabel("Dimensione del problema (N)")
    plt.ylabel("Memoria massima allocata (MB)")
    plt.legend()
    plt.grid(True)

    plt.tight_layout()
    plt.savefig(out_path, dpi=300)
    plt.close()
    print(f"\nBenchmark completato! Grafico salvato in '{out_path}'.")

def main():
    for n in N_VALUES:
        print(f"\n--- Testing N={n} (range x(1..n)) ---")
        
        # Comando per Clingo Standard: il dominio arriva da __.common_range.lp
        cmd_std = [CLINGO_STD, FILE_RANGE, FILE_STD, f"-c n={n}"]
        time_std, mem_std = run_command(cmd_std)
        results["std"]["time"].append(time_std)
        results["std"]["memory"].append(mem_std)
        time_std_str, mem_std_str = format_metric(time_std, mem_std)
        print(f"STD -> Tempo: {time_std_str} | Memoria: {mem_std_str}")
        
        # Comando per Clingo Modificato: stesso dominio del baseline
        cmd_mod = [CLINGO_MOD, FILE_RANGE, FILE_MOD, "-n", "1", f"-c n={n}"]
        time_mod, mem_mod = run_command(cmd_mod)
        results["mod"]["time"].append(time_mod)
        results["mod"]["memory"].append(mem_mod)
        time_mod_str, mem_mod_str = format_metric(time_mod, mem_mod)
        print(f"MOD -> Tempo: {time_mod_str} | Memoria: {mem_mod_str}")

    # --- Generazione dei Grafici ---
    generate_graphs()

if __name__ == "__main__":
    main()