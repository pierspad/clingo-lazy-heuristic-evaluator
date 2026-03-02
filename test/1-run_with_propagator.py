import json
import clingo
from collections import defaultdict
from collections import namedtuple

ENCODING_FILE = "./encoding-no-sum.lp"
INSTANCE = "./instance.lp"

# 1) - il nogood deve essere l'insieme minimo dei nodi che soddisfa quei vincoli

# 2) - nogood proattivo

class CapacityPropagator:
    def __init__(self):
        # Mappa il letterale interno del solver alle informazioni utili durante il solving
        # Formato: solver_literal -> (item_id, bin_id, peso_item)
        self.lit_mapping = {}
        
        # Mappa l'id del bin alla sua capacità specifica
        # Formato: bin_id -> capacity
        self.bin_capacities = {}

        self.my_mapping = defaultdict(lambda: (0, []))

    def init(self, init_context):
        # 1. Estrazione delle capacità variabili dal predicato capacity/2
        for atom in init_context.symbolic_atoms.by_signature("capacity", 2):
            bin_id = atom.symbol.arguments[0].number
            cap = atom.symbol.arguments[1].number
            self.bin_capacities[bin_id] = cap

        # 2. Estrazione dei pesi dal predicato weight/2
        weights = {}
        for atom in init_context.symbolic_atoms.by_signature("weight", 2):
            item_id = atom.symbol.arguments[0].number
            w = atom.symbol.arguments[1].number
            weights[item_id] = w

        # 3. Impostazione dei watch sui letterali assign/2
        for atom in init_context.symbolic_atoms.by_signature("assign", 2):
            item_id = atom.symbol.arguments[0].number
            bin_id = atom.symbol.arguments[1].number
            
            # Convertiamo la rappresentazione simbolica nel letterale intero usato dal CDNL solver
            lit = init_context.solver_literal(atom.literal)
            
            # Registriamo un watch: il solver chiamerà il metodo propagate() 
            # quando questo letterale diventerà vero durante l'esplorazione dell'albero di ricerca
            init_context.add_watch(lit)
            
            # Salviamo il mapping per avere accesso immediato (O(1)) ai dati in fase di propagazione
            if item_id in weights:
                self.lit_mapping[lit] = (item_id, bin_id, weights[item_id])


    def find_minimum_set(slit_list, bin_capacity):
        helper_list = {}
        for slit in slit_list:
            helper_list[slit] = self.lit_mapping[slit][2]
        
        sorted_list = sorted(helper_list.items(), key=lambda x: x[1], reverse=True)

        weight = 0
        list_to_return = []

        for elem, w in sorted_list:
            weight += w
            list_to_return.append(slit)

            if weight > bin_capacity:
                break
        
        return list_to_return


    def propagate(self, control, changes):
        # per ogni change ci contiamo i pesi che aggiunge a quel bidone
        for slit in changes:
            item_id, bin_id, weight_to_add = self.lit_mapping[slit]

            weight_loaded, items_list = self.my_mapping[bin_id]
            weight_loaded = weight_loaded + weight_to_add 
            items_list.append(slit)
            self.my_mapping[bin_id] = (weight_loaded, items_list)

            capacity_current_bin = self.bin_capacities[bin_id]
            weight_current_bin = self.my_mapping[bin_id][0]

            if(weight_current_bin > capacity_current_bin):
                # control.add_nogood restituisce False se il nogood appena aggiunto
                # rende l'assegnamento corrente inconsistente (conflicting)
                minimum_set = self.find_minimum_set(items_list, capacity_current_bin)

                if not control.add_nogood(minimum_set):
                    # Il solver è ora in stato di conflitto. 
                    # Dobbiamo interrompere immediatamente il loop di propagazione.
                    return


    def undo(self, thread_id, assignment, changes):
        # per ogni change ci contiamo i pesi che rimuoviamo da quel bidone
        for ch in changes:
            item_id, bin_id, weight_to_subtract = self.lit_mapping[ch]

            weight_loaded, items_list = self.my_mapping[bin_id]

            if ch in items_list:
                weight_loaded = weight_loaded - weight_to_subtract 
                items_list.remove(ch)
                self.my_mapping[bin_id] = (weight_loaded, items_list)



def on_model(model):
    print("\n--- New AS found ---")

    for atomo in model.symbols(shown=True):
        if atomo.name == "assign":
            print(str(atomo))

    if model.cost:
        print(f"Costo di questa soluzione: {model.cost}")


def main():
    print(f"Clingo library version: {clingo.__version__}")
    ctrl = clingo.Control(["--configuration=frumpy", "--stats"])


    propagator = CapacityPropagator()
    ctrl.register_propagator(propagator)


    ctrl.load(ENCODING_FILE)
    ctrl.load(INSTANCE)
    ctrl.ground([("base", [])])


    result = ctrl.solve(on_model=on_model)
    print(f"\nAnswer Set: {result}")

    stats = ctrl.statistics
    print(json.dumps(stats, indent=4))


    total_cpu_time = stats["summary"]["times"]["cpu"]
    solving_time = stats['summary']['times']['solve']


    print(f"\nTotal CPU Time(Clingo): {total_cpu_time}")
    print(f"Total Solving time(Clingo): {solving_time}")


if __name__ == "__main__":
    main()


