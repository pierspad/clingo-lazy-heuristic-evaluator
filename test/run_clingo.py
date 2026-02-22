import clingo

def on_model(model):
    atomi = model.symbols(shown=True)

    print("\n--- Nuovo AS trovato ---")

    print()






def main():

    ctrl = clingo.Control()

    print("Caricamento file...")
    ctrl.load("encoding.lp")
    ctrl.load("facts.lp")

    print("Inizio grounding...")
    ctrl.ground([("base", [])])

    print("Inizio Soling...")
    risultato = ctrl.solve(on_model=on_model)

    print(f"\nRicerca terinata. Stato finale: {risultato}")

if __name__ == "__main__":
    main()
