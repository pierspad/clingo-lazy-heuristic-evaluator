import clingo
import time

def solve_without_heuristics(graph_file, coloring_file):
    """
    Esegue il solver Clingo SENZA euristiche e misura il tempo di esecuzione.
    """
    print("--- Esecuzione di Clingo SENZA euristiche ---\n")
    
    # Leggi i file
    with open(graph_file, "r") as f:
        graph_code = f.read()
    
    with open(coloring_file, "r") as f:
        coloring_code = f.read()
    
    # Unisci i programmi
    full_program = graph_code + "\n" + coloring_code
    
    print("Programma ASP caricato (senza euristiche)")
    print("-------------------------------------------")

    # Crea un'istanza del controllo di Clingo
    ctl = clingo.Control(["-n", "1"])
    
    try:
        # Aggiungi il programma al controllo
        ctl.add("base", [], full_program)
        
        # Esegui il grounding
        print("Grounding...")
        start_ground = time.time()
        ctl.ground([("base", [])])
        end_ground = time.time()
        print(f"Grounding completato in {end_ground - start_ground:.4f} secondi\n")
        
        # Risolvi il problema e misura il tempo
        print("Solving...")
        start_solve = time.time()
        
        with ctl.solve(yield_=True) as handle:
            found_solution = False
            for model in handle:
                found_solution = True
                end_solve = time.time()
                solving_time = end_solve - start_solve
                total_time = end_solve - start_ground
                
                print(f"\n✓ Soluzione trovata!")
                solution = [str(atom) for atom in model.symbols(shown=True)]
                print("Assegnazione colori:")
                for atom in sorted(solution):
                    print(f"  {atom}")
                
                print(f"\n--- Statistiche temporali ---")
                print(f"Tempo di grounding: {end_ground - start_ground:.4f} secondi")
                print(f"Tempo di solving:   {solving_time:.4f} secondi")
                print(f"Tempo totale:       {total_time:.4f} secondi")
                
            if not found_solution:
                end_solve = time.time()
                print("\n✗ Nessuna soluzione trovata.")
                print(f"Tempo totale: {end_solve - start_ground:.4f} secondi")

    except Exception as e:
        print(f"\nErrore durante l'esecuzione di Clingo: {e}")
        import traceback
        traceback.print_exc()


def main():
    """
    Funzione principale.
    """
    try:
        # File paths
        graph_file = "graph_instance.lp"
        coloring_file = "coloring.lp"
        
        print("="*50)
        print("  Graph Coloring - SENZA Euristiche")
        print("="*50 + "\n")
        
        # Risolvi senza euristiche
        solve_without_heuristics(graph_file, coloring_file)
        
        print("\n" + "="*50)

    except FileNotFoundError as e:
        print(f"Errore: file non trovato - {e}")
        print("Assicurati che i file 'graph_instance.lp' e 'coloring.lp' siano nella stessa directory.")
    except Exception as e:
        print(f"Si è verificato un errore imprevisto: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
