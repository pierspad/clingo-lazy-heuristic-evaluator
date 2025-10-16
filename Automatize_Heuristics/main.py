import os
import clingo
import google.generativeai as genai
from dotenv import load_dotenv
import re
import time

def get_llm_heuristic(graph_instance, colors):
    print("Chiedo all'LLM di generare euristiche...")
    try:
        load_dotenv()
        api_key = os.getenv("GOOGLE_API_KEY")
        if not api_key:
            raise ValueError("La variabile d'ambiente GOOGLE_API_KEY non è stata impostata.")

        genai.configure(api_key=api_key)

        model = genai.GenerativeModel('gemini-2.5-flash')

        contents = f"""
        Sei un esperto di Answer Set Programming e devi generare euristiche per guidare il solver Clingo
        nella risoluzione di un problema di Graph Coloring.

        Grafo:
        {graph_instance}

        Colori disponibili: {', '.join(colors)}

        IMPORTANTE: Devi fornire SOLO direttive #heuristic per Clingo, NON un'assegnazione completa.
        
        Le euristiche devono essere nel formato SEMPLICE:
        #heuristic color(NODO, COLORE). [PESO@PRIORITA, MODIFICATORE]
        
        Dove:
        - NODO è un numero specifico (1, 2, 3, 4, ecc.)
        - COLORE è uno dei colori disponibili
        - PESO è un numero positivo (più alto = più preferito, range 1-10)
        - PRIORITA è il livello di priorità (usa 1)
        - MODIFICATORE è 'true' (preferisci questa assegnazione) o 'false' (evita questa assegnazione)
        
        NON usare variabili (N, C, X) nelle euristiche.
        NON usare condizioni (:- ...) nelle euristiche.
        USA SOLO valori concreti.
        
        Esempi VALIDI:
        #heuristic color(1, red). [10@1, true]
        #heuristic color(2, green). [8@1, true]
        #heuristic color(3, blue). [5@1, true]
        #heuristic color(4, red). [3@1, false]
        
        Analizza la struttura del grafo e suggerisci euristiche intelligenti:
        - Identifica i nodi con più connessioni (gradi più alti)
        - Assegna pesi più alti ai nodi critici
        - Suggerisci colori diversi per nodi adiacenti
        
        Fornisci la tua risposta SOLO come lista di direttive #heuristic, una per riga.
        NON includere spiegazioni, commenti, backticks markdown o altro testo.
        """

        response = model.generate_content(contents)
        print("Euristiche ricevute dall'LLM:")
        print(response.text)
        return response.text

    except Exception as e:
        print(f"Errore durante la chiamata all'LLM: {e}")
        return ""

def parse_llm_heuristics(response_text):
    heuristics = []
    lines = response_text.strip().split('\n')
    
    for line in lines:
        line = line.strip()
        # Rimuovi backticks markdown se presenti
        line = line.replace('`', '')
        
        # Cerca linee che contengono #heuristic
        if line.startswith('#heuristic'):
            # Verifica che non contenga variabili (lettere maiuscole singole) o condizioni (:-) 
            if ':-' not in line and not re.search(r'\b[A-Z]\b', line):
                heuristics.append(line)
            else:
                print(f"Euristica ignorata (contiene variabili o condizioni): {line}")
        # Se l'LLM ha usato altri formattatori, estrai la parte con #heuristic
        elif '#heuristic' in line:
            match = re.search(r'(#heuristic\s+[^:]+\[[^\]]+\])', line)
            if match:
                heuristic = match.group(1)
                # Verifica che non contenga variabili o condizioni
                if ':-' not in heuristic and not re.search(r'\b[A-Z]\b', heuristic):
                    heuristics.append(heuristic)
                else:
                    print(f"Euristica ignorata (contiene variabili o condizioni): {heuristic}")
    
    return heuristics

def solve_with_clingo(graph_file, coloring_file, heuristics):
    print("\n--- Esecuzione di Clingo con le euristiche ---")
    
    # Leggi i file
    with open(graph_file, "r") as f:
        graph_code = f.read()
    
    with open(coloring_file, "r") as f:
        coloring_code = f.read()
    
    # Unisci tutto insieme
    full_program = graph_code + "\n" + coloring_code + "\n" + "\n".join(heuristics)
    
    print("Programma ASP completo inviato al solver:")
    print(full_program)
    print("-------------------------------------------")

    # Crea un'istanza del controllo di Clingo
    ctl = clingo.Control(["--heuristic=Domain", "-n", "1"])
    
    try:
        # Aggiungi il programma al controllo
        ctl.add("base", [], full_program)
        
        # Esegui il grounding
        print("Grounding...")
        start_ground = time.time()
        ctl.ground([("base", [])])
        end_ground = time.time()
        print(f"Grounding completato in {end_ground - start_ground:.4f} secondi\n")
        
        # Risolvi il problema
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
        print(f"Errore durante l'esecuzione di Clingo: {e}")
        import traceback
        traceback.print_exc()


def main():
    try:
        # File paths
        graph_file = "graph_instance.lp"
        coloring_file = "coloring.lp"
        
        # 1. Leggi l'istanza del grafo per passarla all'LLM
        with open(graph_file, "r") as f:
            graph_instance = f.read()

        # Colori disponibili (leggili dal file coloring.lp o definiscili qui)
        colors = ["red", "green", "blue"]

        # 2. Chiedi all'LLM di generare euristiche direttamente
        llm_heuristics_text = get_llm_heuristic(graph_instance, colors)

        # 3. Estrai le euristiche dalla risposta
        heuristics = parse_llm_heuristics(llm_heuristics_text)
        
        if heuristics:
            print("\nEuristiche estratte per Clingo:")
            for h in heuristics:
                print(h)
        else:
            print("\nNessuna euristica valida generata dalla risposta dell'LLM.")
            print("Procedo comunque con il solver senza euristiche.")

        # 4. Risolvi con Clingo usando le euristiche
        solve_with_clingo(graph_file, coloring_file, heuristics)

    except FileNotFoundError as e:
        print(f"Errore: file non trovato - {e}")
        print("Assicurati che i file 'graph_instance.lp' e 'coloring.lp' siano nella stessa directory.")
    except Exception as e:
        print(f"Si è verificato un errore imprevisto: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
