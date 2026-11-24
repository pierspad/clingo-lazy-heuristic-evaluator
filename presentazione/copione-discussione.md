# Copione della discussione

Dodici slide in inglese e due slide di riserva, con un esempio comune per introdurre problema, implementazione e semantica.

## 1. Lazy Declarative Heuristics in Answer Set Programming

**Da proiettare.** Titolo ufficiale, Pierpaolo Spadafora, matricola 263722, relatori con titoli e atenei.

**Da dire.** In Answer Set Programming, we describe what makes a solution valid. A heuristic tells the solver which choice to try next. In this thesis I look at heuristics that need to know what the solver has already assigned. That information becomes available during search, but in clingo a conventional heuristic directive is grounded before search begins. I built a propagator to evaluate these heuristics on the current assignment.

## 2. One heuristic rule, two ways to use it

**Da dire.** Each item can be chosen, and a larger number gets a higher preference. For four item facts, grounding produces the four directives on the left. Our lazy evaluator keeps one template and registers the candidate literals. As assignments change, it updates its state. When clingo asks for a choice, it can propose the best available literal without generating those four ground heuristic directives. The base program still goes through grounding.

## 3. Where should 1 go?

**Da dire.** B sums to four and C to five. We want to place one in the lighter set, B. Look at just this one target in the bound-based ground simulation. A stands for the sum of the values assigned to C. The possible sums run from zero through ten. Each line has a different bound and a different weight. Read down the first column. At sum five the last enabled bound is five and its weight is twenty-six. For C of one the opposite sum is four, giving a weight of twenty-one. That is how B wins. Across two sets and four numbers we need eighty-eight directives. For this benchmark the number of bounds per target grows quadratically and the total grows cubically.

## 4. The C++ propagator uses the heuristic interface

**Da dire.** Init registers candidate literals and watches, then control passes to clingo. A watched literal becoming true triggers propagate. It updates the heuristic state. A branching request triggers decide, which returns the preferred literal. Backtracking triggers undo, which restores the state. Follow each pair of arrows as a separate event.

## 5. SWI-Prolog queries the trail

**Da dire.** After initialization, clingo asks decide for a literal. The backend runs the Prolog query against the current trail. Each answer proposes a target, weight, priority and modifier. C++ maps the proposals to solver literals, keeps eligible targets and returns the best literal through decide to clingo.

## 6. Differences between semantics

**Da proiettare.** Tre differenze. Negazione su atomo libero, aggregato dinamico, massimo vuoto.

**Da dire.** Suppose C of four is still unassigned. A clingo-like negative guard waits until its atom is established false. An Alpha-like negative guard can already hold while the atom is unassigned. This concerns the heuristic condition, not the truth of the atom in the solution. For the dynamic aggregate equalities studied here, the clingo-like evaluation waits for the value to be fixed. The Alpha-like evaluation uses the atoms currently true. A third difference is the value of an empty maximum. Alpha uses zero, and clingo uses negative infinity.

## 7. Four ways to evaluate a heuristic

**Da proiettare.** Matrice ground/lazy × clingo-like/Alpha-like.

**Da dire.** I crossed the representation with the reading of the partial assignment, and included a baseline without domain heuristics. The four variants run in clingo. The ground Alpha-like version simulates that reading with transformations such as bound-guarded unrolling. Those transformations have limits. On HRP, for example, the ground simulation drops some capacity guards, so it can suggest different choices from the lazy version. I also use the Alpha solver itself as an external comparison.

## 8. BSP search drops to 120 choices

**Da proiettare.** Grafico BSP delle scelte per dimensione e dato a n = 120.

**Da dire.** The baseline and lazy clingo-like choice counts agree because the lazy clingo-like heuristic finds no applicable candidates during search on this encoding. The Alpha-like variant can guide the solver while the targets are still free, reaching a solution in one hundred and twenty choices with no conflicts. Solving takes about four hundredths of a second, but grounding still takes around one hundred and fifty-four seconds. The base program remains a major cost in this BSP encoding.

## 9. BSP choices with ga hidden

**Da dire.** Here I hide the ground Alpha-like simulation so we can follow the other curves. With one hundred and twenty items the unguided solver makes over seventy-eight thousand choices. Lazy Alpha-like guidance needs one hundred and twenty. The expensive part that remains is grounding the base program.

## 10. PUP uses nearly half the time and memory

**Da proiettare.** Grafico della memoria al crescere di N e confronto su double-200, entrambi Alpha-like. Tempo interno 438.6 e 224.0 s. Picco di memoria 24.4 e 12.7 GB.

**Da dire.** The Partner Units Problem allocates zones and sensors to units under capacity and connectivity constraints. The unguided baseline reaches size eighty. Both Alpha-like variants solve the published suite through size two hundred. On that largest instance, lazy evaluation brings total clingo time down to about two hundred and twenty-four seconds and peak memory to twelve point seven gigabytes. Most of the difference in runtime comes from grounding.

## 11. Where does heuristic laziness pay off?

**Da proiettare.** BSP, grounding del programma. PUP, costo dell’euristica ground. HRP, costo della singola decisione.

**Da dire.** The most important cost varies across these problems. On BSP, the grounding of the base encoding can dominate. On PUP, heuristic laziness saves time and memory on the same solved instance. On the largest House Reconfiguration instance, the embedded Prolog backend spends roughly ninety-four percent of its time inside the propagator. This shows why we measured the work per decision as well as the number of decisions. My contribution is a way to evaluate a declarative heuristic on the current search state within clingo’s ground-and-solve architecture.

**Sul risultato HRP.** Both lazy variants execute heuristic rules. On house-14, the Alpha-like reading gives the intended placement order in 86 choices. Under the clingo-like reading some placement conditions become available too late, while other directives can already guide search. This takes 66,717 choices. The benefit here comes from when the rules apply, even without a dynamic aggregate.

## 12. Thank you

Thank you for your attention. I would be happy to take questions.

## 13. Why does the ground BSP ranking deteriorate?

Different weights become indistinguishable at the upper limit of the 16-bit field. The lazy backend ranks candidates internally. How much this matters depends on how much search relies on the ranking.

## 14. How does the separate Alpha solver compare?

On double-200, Alpha and lazy clingo have similar peak memory, but Alpha finishes faster. On house-20 native lazy clingo is faster. The PUP times on this backup slide are external wall times. The main results slide uses clingo’s internal time.

### Per le domande

- BSP compatto, tab. 5.12. A n = 200, baseline 604 regole, lazy Alpha-like 606, ground Alpha-like 8,101,503.
- Ranking, §§3.1.3–3.1.4. Il campo a 16 bit di clasp può saturare e cancellare distinzioni tra pesi.
- Alpha, §5.9. Su double-200 ha memoria di picco simile a lazy C++ e tempo inferiore. Su house-20 lazy C++ è più veloce delle configurazioni Alpha testate.
- Protocollo, §6.2. Una esecuzione per configurazione e istanza.


