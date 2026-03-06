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
        
        self.lit_mapping = {}   # slit -> (item_id, bin_id, weight)
        self.inverse_lit_mapping = {} # (item_id, bin_id) -> slit

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
                self.inverse_lit_mapping[(item_id, bin_id)] = slit
        



    def _get_minimal_conflict(self, current_slits, limit):
        # per ogni solver literal presente nell'assegnamento che ha sforato dal
        # bin corrente aggiungi alla lista insieme al peso e poi ordina decrescente 
        slits_with_weights = [(s, self.lit_mapping[s][2]) for s in current_slits]
        slits_with_weights.sort(key=lambda x: x[1], reverse=True)
        
        core = []
        accum_weight = 0
        for slit, w in slits_with_weights:
            core.append(slit)
            accum_weight += w
            if accum_weight > limit:
                break
        return core


    def propagate(self, control, changes):
        modified_bins = set()

        # 1. AGGIORNAMENTO STATO INTERNO (processiamo tutti i cambiamenti prima)
        for slit in changes:
            _, bin_id, weight = self.lit_mapping[slit]
            bin_data = self.bin_state[bin_id]

            bin_data['current_weight'] += weight
            bin_data['slits'].append(slit)
            modified_bins.add(bin_id)

        # 2 & 3. CONTROLLI SUI BIN MODIFICATI
        for bin_id in modified_bins:
            bin_data = self.bin_state[bin_id]
            current_bin_limit = self.bin_capacities[bin_id]

            # 2. CONTROLLO REATTIVO (Siamo in conflitto?)
            if bin_data['current_weight'] > current_bin_limit:
                core = self._get_minimal_conflict(bin_data['slits'], current_bin_limit)
                if not control.add_nogood(core):
                    return
                # Se siamo in conflitto reattivo, saltiamo il proattivo per questo bin
                continue 
                
            # 3. CONTROLLO PROATTIVO (Inferenza per Unit Propagation)
            remaining_weight = current_bin_limit - bin_data["current_weight"]

            for item_id, w in self.items_sorted:
                # Grazie all'ordinamento, se w ci sta, ci staranno anche i successivi
                if w <= remaining_weight:
                    break

                slit_scelto = self.inverse_lit_mapping.get((item_id, bin_id))

                # Se l'item non esiste o è già nel bin, ignoriamo
                if slit_scelto is None or slit_scelto in bin_data["slits"]:
                    continue

                # Calcoliamo il core parziale che, unito all'item corrente, sfora la capacità
                """ potrei tranquillamente fare, ma un pelino di performance si risparmiano così
                core = self._get_minimal_conflict(bin_data['slits'].append(self.inverse_lit_mapping(item_id,bin_id)), limit_for_existing)
                """
                limit_for_existing = current_bin_limit - w
                core = self._get_minimal_conflict(bin_data['slits'], limit_for_existing)

                # Creiamo il nogood aggiungendo l'item vietato
                core.append(slit_scelto)
                
                # Iniettiamo il nogood per forzare la propagazione a False di slit_scelto
                if not control.add_nogood(core):
                    return



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


