import json
import clingo

ENCODING_FILE = "./encoding-no-sum.lp"
INSTANCE = "./instance.lp"

class CapacityPropagator:
    def __init__(self):
        self.bin_capacities = {}
        self.item_weights = {}

    def init(self, init):
        # 1. Estrai dinamicamente le capacità dei bin dall'istanza ASP
        for atom in init.symbolic_atoms.by_signature("capacity", 2):
            bin_id = atom.symbol.arguments[0].number
            cap = atom.symbol.arguments[1].number
            self.bin_capacities[bin_id] = cap

        # 2. Estrai dinamicamente i pesi degli item dall'istanza ASP
        for atom in init.symbolic_atoms.by_signature("weight", 2):
            item_id = atom.symbol.arguments[0].number
            weight = atom.symbol.arguments[1].number
            self.item_weights[item_id] = weight


    def propagate(self, control, changes):
        pass



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


