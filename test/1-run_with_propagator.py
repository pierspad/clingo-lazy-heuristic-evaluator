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
        # --- STATO STATICO (Sola lettura durante il solving) ---
        self.bin_capacities = {}  # bin_id -> capacity
        self.lit_mapping = {}     # slit -> (item_id, bin_id, weight)
        self.items_sorted = []    # lista ordinata di tuple: (item_id, weight)

        # --- STATO DINAMICO (Modificato da propagate e undo) ---
        # bin_id -> {'current_weight': int, 'slits': list}
        self.bin_state = defaultdict(lambda: {'current_weight': 0, 'slits': []})

    def init(self, init_context):
        # 1. Estrazione capacità
        for atom in init_context.symbolic_atoms.by_signature("capacity", 2):
            bin_id = atom.symbol.arguments[0].number
            cap = atom.symbol.arguments[1].number
            self.bin_capacities[bin_id] = cap

        # 2. Estrazione pesi
        weights = {}
        for atom in init_context.symbolic_atoms.by_signature("weight", 2):
            item_id = atom.symbol.arguments[0].number
            w = atom.symbol.arguments[1].number
            weights[item_id] = w
            self.items_sorted.append((item_id, w))

        # Prepariamo già la lista globale ordinata per peso decrescente
        self.items_sorted.sort(key=lambda x: x[1], reverse=True)

        # 3. Impostazione watch sui solver literals
        for atom in init_context.symbolic_atoms.by_signature("assign", 2):
            item_id = atom.symbol.arguments[0].number
            bin_id = atom.symbol.arguments[1].number
            slit = init_context.solver_literal(atom.literal)
            
            init_context.add_watch(slit)
            
            if item_id in weights:
                self.lit_mapping[slit] = (item_id, bin_id, weights[item_id])



    def _get_minimal_conflict(self, current_slits, limit):
        # per ogni solver literal nell'assegnamento che sfora dal bin corrente aggiungi
        # alla lista insieme al peso e poi ordina decrescente 
        slits_with_weights = [(s, self.lit_mapping[s][2]) for s in current_slits]
        slits_with_weights.sort(key=lambda x: x[1], reverse=True)
        
        core = []
        acc_weight = 0
        for slit, w in slits_with_weights:
            core.append(slit)
            acc_weight += w
            if acc_weight > limit:
                break
        return core


    def propagate(self, control, changes):
        for slit in changes:
            # Recuperiamo le info statiche e lo stato dinamico del bin
            item_id, bin_id, weight = self.lit_mapping[slit]
            bin_data = self.bin_state[bin_id]

            # 1. AGGIORNAMENTO STATO INTERNO
            bin_data['current_weight'] += weight
            bin_data['slits'].append(slit)

            # 2. CONTROLLO REATTIVO (Siamo in conflitto?)
            current_bin_limit = self.bin_capacities[bin_id]
            if bin_data['current_weight'] > current_bin_limit:
                
                core = self._get_minimal_conflict(bin_data['slits'], current_bin_limit)
                
                # Se l'assegnamento collassa, torniamo il controllo per il backjumping
                if not control.add_nogood(core):
                    return

        # controllo proattivo per trovare i nogood
        # se siamo qui è perchè dopo aver controllato i slit turnati a vero per ora
        # nel bin corrente c'è ancora spazio, quindi tocca trovare quali sono altri cor


    def undo(self, thread_id, assignment, changes):
        for slit in changes:
            _, bin_id, weight = self.lit_mapping[slit]
            state = self.bin_state[bin_id]

            # Ripristino tollerante (idempotente)
            if slit in state['slits']:
                state['current_weight'] -= weight
                state['slits'].remove(slit)




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


