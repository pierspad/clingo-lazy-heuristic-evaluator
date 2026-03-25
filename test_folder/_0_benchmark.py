import subprocess
import re
import matplotlib.pyplot as plt

# Configurazioni
N_VALUES = range(10, 101, 10)  # Da N=10 a N=100 con step 10
CLINGO_STD = "clingo"
CLINGO_MOD = "/home/ribben/Desktop/clingo-lazy-heuristics/clingo-modified/build/bin/clingo"
FILE_STD = "__BSP.lp"
FILE_MOD = "_2_non_ground.lp"

# Dizionari per salvare i risultati
results = {
    "std": {"time": [], "memory": []},
    "mod": {"time": [], "memory": []}
}

def run_command(command):
    """Esegue un comando con /usr/bin/time -v e ne estrae tempo e memoria (RSS)."""
    # Usa /usr/bin/time -v per profilare memoria e tempo
    full_cmd = ["/usr/bin/time", "-v"] + command
    
    print(f"Eseguendo: {' '.join(full_cmd)}")
    
    try:
        # Catturiamo sia stdout che stderr (time stampa le statistiche su stderr)
        process = subprocess.run(full_cmd, capture_output=True, text=True, check=False)
        output = process.stderr  # time -v scrive qui
        
        # Estraiamo l'RSS in kbytes
        mem_match = re.search(r"Maximum resident set size \(kbytes\):\s+(\d+)", output)
        # Estraiamo il tempo reale in secondi
        time_match = re.search(r"User time \(seconds\):\s+([\d.]+)", output) 
        # Oppure il Wall clock time: r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s+(.+)"
        
        if mem_match and time_match:
            memory_mb = int(mem_match.group(1)) / 1024.0  # Converti KB in MB
            time_sec = float(time_match.group(1))
            return time_sec, memory_mb
        else:
            print("Errore nel parsing dell'output di time.")
            return None, None
            
    except Exception as e:
        print(f"Errore durante l'esecuzione: {e}")
        return None, None

def main():
    for n in N_VALUES:
        print(f"\n--- Testing N={n} ---")
        
        # Comando per Clingo Standard (passiamo la costante n tramite -c)
        cmd_std = [CLINGO_STD, FILE_STD, f"-c n={n}"]
        time_std, mem_std = run_command(cmd_std)
        results["std"]["time"].append(time_std)
        results["std"]["memory"].append(mem_std)
        print(f"STD -> Tempo: {time_std:.2f} s | Memoria: {mem_std:.2f} MB")
        
        # Comando per Clingo Modificato
        cmd_mod = [CLINGO_MOD, FILE_MOD, "-n", "1", f"-c n={n}"]
        time_mod, mem_mod = run_command(cmd_mod)
        results["mod"]["time"].append(time_mod)
        results["mod"]["memory"].append(mem_mod)
        print(f"MOD -> Tempo: {time_mod:.2f} s | Memoria: {mem_mod:.2f} MB")

    # --- Generazione dei Grafici ---
    plt.figure(figsize=(12, 5))

    # Grafico 1: Tempo
    plt.subplot(1, 2, 1)
    plt.plot(list(N_VALUES), results["std"]["time"], marker='o', label='Clingo Standard', color='red')
    plt.plot(list(N_VALUES), results["mod"]["time"], marker='s', label='Clingo Lazy (Modificato)', color='green')
    plt.title('Tempo di esecuzione')
    plt.xlabel('Dimensione del problema (N)')
    plt.ylabel('Tempo (Secondi)')
    plt.legend()
    plt.grid(True)

    # Grafico 2: Memoria
    plt.subplot(1, 2, 2)
    plt.plot(list(N_VALUES), results["std"]["memory"], marker='o', label='Clingo Standard', color='red')
    plt.plot(list(N_VALUES), results["mod"]["memory"], marker='s', label='Clingo Lazy (Modificato)', color='green')
    plt.title('Consumo di Memoria (RSS)')
    plt.xlabel('Dimensione del problema (N)')
    plt.ylabel('Memoria massima allocata (MB)')
    plt.legend()
    plt.grid(True)

    plt.tight_layout()
    plt.savefig('benchmark_results.png', dpi=300)
    print("\nBenchmark completato! I grafici sono stati salvati in 'benchmark_results.png'.")
    plt.show()

if __name__ == "__main__":
    main()