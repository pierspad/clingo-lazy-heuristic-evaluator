import argparse
import random

def generate_instance(num_bins, num_items, min_cap, max_cap, filename):
    # 1. Generiamo le capacità eterogenee per ogni bin
    bin_capacities = {b: random.randint(min_cap, max_cap) for b in range(1, num_bins + 1)}
    total_capacity = sum(bin_capacities.values())

    # Controllo di sicurezza logica globale
    if num_items > total_capacity:
        print("Errore: Troppi oggetti per la capacità totale. Impossibile garantire pesi interi >= 1.")
        return

    # 2. Assegnamento "segreto"
    bin_assignments = {b: [] for b in range(1, num_bins + 1)}
    for item_id in range(1, num_items + 1):
        b = random.randint(1, num_bins)
        bin_assignments[b].append(item_id)

    # 3. Generazione dei pesi basata sulla capacità specifica del bin
    weights = {}
    for b, items in bin_assignments.items():
        if not items:
            continue
            
        rem_cap = bin_capacities[b] # Usiamo la capacità specifica di QUESTO bin
        for idx, item in enumerate(items):
            items_left = len(items) - idx - 1
            
            if items_left == 0:
                max_w = rem_cap
                w = random.randint(1, max_w) if max_w >= 1 else 1
            else:
                max_w = rem_cap - items_left
                w = random.randint(1, max_w) if max_w >= 1 else 1
            
            weights[item] = w
            rem_cap -= w

    # 4. Scrittura del file ASP
    with open(filename, 'w') as f:
        # Scriviamo i bin e le loro capacità
        for b, cap in bin_capacities.items():
            f.write(f"bin({b}).\n")
            f.write(f"capacity({b}, {cap}).\n")
        f.write("\n")
        
        # Scriviamo gli item e i loro pesi
        for item_id in range(1, num_items + 1):
            f.write(f"item({item_id}).\n")
            f.write(f"weight({item_id}, {weights[item_id]}).\n")

    print(f"Istanza generata con successo in: {filename}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Genera istanze fattibili di Bin Packing eterogeneo.")
    parser.add_argument("-b", "--bins", type=int, required=True, help="Numero di bin")
    parser.add_argument("-i", "--items", type=int, required=True, help="Numero di item")
    parser.add_argument("--min-cap", type=int, required=True, help="Capacità minima generabile")
    parser.add_argument("--max-cap", type=int, required=True, help="Capacità massima generabile")
    parser.add_argument("-f", "--file", type=str, default="instance.lp", help="Nome file di output")
    
    args = parser.parse_args()
    generate_instance(args.bins, args.items, args.min_cap, args.max_cap, args.file)