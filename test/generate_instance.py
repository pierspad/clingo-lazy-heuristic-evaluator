import argparse
import random


def generate_instance(num_bins, num_items, capacity, filename):
    # Controllo di sicurezza: ogni oggetto deve pesare almeno 1
    if num_items > num_bins * capacity:
        print("Errore: Troppi oggetti per la capacità totale. Impossibile garantire pesi interi >= 1.")
        return

    # 1. Assegniamo casualmente (e segretamente) ogni oggetto a un bin
    bin_assignments = {b: [] for b in range(1, num_bins + 1)}
    for item_id in range(1, num_items + 1):
        b = random.randint(1, num_bins)
        bin_assignments[b].append(item_id)

    # 2. Generiamo i pesi rispettando la capacità di ciascun bin
    weights = {}
    for b, items in bin_assignments.items():
        if not items:
            continue
            
        rem_cap = capacity
        for idx, item in enumerate(items):
            items_left = len(items) - idx - 1
            
            if items_left == 0:
                # Ultimo oggetto nel bin: gli diamo un peso casuale fino al rimanente
                # (Non usiamo tutto rem_cap per forza, così i bin non sono per forza pieni al 100%, 
                # rendendo il problema più vario).
                max_w = rem_cap
                w = random.randint(1, max_w) if max_w >= 1 else 1
            else:
                # Lascia almeno 1 di spazio per ogni oggetto rimanente in questo bin
                max_w = rem_cap - items_left
                # Per rendere il problema difficile, diamo un peso casuale nel range disponibile
                w = random.randint(1, max_w) if max_w >= 1 else 1
            
            weights[item] = w
            rem_cap -= w

    # 3. Scriviamo il file ASP
    with open(filename, 'w') as f:
        f.write(f"#const capacity = {capacity}.\n\n")
        f.write(f"bin(1..{num_bins}).\n\n")
        
        # Scriviamo gli item e i pesi in ordine logico, mascherando l'assegnamento segreto
        for item_id in range(1, num_items + 1):
            f.write(f"item({item_id}).\n")
            f.write(f"weight({item_id}, {weights[item_id]}).\n")

    print(f"Istanza generata con successo in: {filename}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Genera istanze fattibili di Bin Packing per ASP.")
    parser.add_argument("-b", "--bins", type=int, required=True, help="Numero di bin a disposizione")
    parser.add_argument("-i", "--items", type=int, required=True, help="Numero di item da inserire")
    parser.add_argument("-c", "--capacity", type=int, required=True, help="Capacità massima di ogni bin")
    parser.add_argument("-f", "--file", type=str, default="instance.lp", help="Nome del file di output (default: instance.lp)")
    
    args = parser.parse_args()
    generate_instance(args.bins, args.items, args.capacity, args.file)