# Copione della discussione

Dieci slide in inglese, con un esempio comune per introdurre problema, implementazione e semantica.

## 1. Lazy Declarative Heuristics in Answer Set Programming

**Da proiettare.** Titolo ufficiale, Pierpaolo Spadafora, matricola 263722, relatori con titoli e atenei.

**Da dire.** In Answer Set Programming, we describe what makes a solution valid. A heuristic tells the solver which choice to try next. In this thesis I look at heuristics that need to know what the solver has already assigned. That information becomes available during search, but in clingo a conventional heuristic directive is grounded before search begins. I built a propagator to evaluate these heuristics on the current assignment.

## 2. Grounding prepares every rule before search

**Da dire.** Read X as a placeholder for an item. This directive suggests choosing b of X, with X as its weight. For four items the grounder prepares four separate preferences before search. Now imagine that the weight depends on a sum that changes with each choice. A lazy evaluator can read that sum when the solver asks for a decision.

## 3. A small heuristic can have a large grounding

**Da dire.** Our goal is to balance two sums. Four is in B, while two and three are in C. Only one remains. The first directive scores placing it in B using the opposite sum, five. The second scores placing it in C using four. The higher score sends one to B, giving five on each side. To prepare these two rules in advance we have four candidate items, two groups and eleven possible sums from zero through ten. That gives eighty-eight ground directives. At size one hundred the same calculation gives over a million.

## 4. Native C++ updates the heuristic

**Da dire.** Init registers the candidate literals and watches before search. Follow the upper pair of arrows when a watched literal becomes true. Propagate updates the running sums and control returns to clingo. If search backtracks, undo reverses those changes. When a branching choice is needed, decide uses the maintained ranking to return a preferred literal.

## 5. SWI-Prolog queries the trail at each decision

**Da dire.** The Prolog backend uses the same callbacks. At a decision it queries the current trail through foreign predicates. Each query result proposes a target, weight, priority and modifier. C++ maps the target back to a free solver literal and selects the best valid proposal. If none applies, clingo uses its fallback.

## 6. Differences between semantics

**Da proiettare.** Tre differenze. Negazione su atomo libero, aggregato dinamico, massimo vuoto.

**Da dire.** Suppose C of four is still unassigned. A clingo-like negative guard waits until its atom is established false. An Alpha-like negative guard can already hold while the atom is unassigned. This concerns the heuristic condition, not the truth of the atom in the solution. For the dynamic aggregate equalities studied here, the clingo-like evaluation waits for the value to be fixed. The Alpha-like evaluation uses the atoms currently true. A third difference is the value of an empty maximum. Alpha uses zero, and clingo uses negative infinity.

## 7. Four ways to evaluate a heuristic

**Da proiettare.** Matrice ground/lazy × clingo-like/Alpha-like.

**Da dire.** I crossed the representation with the reading of the partial assignment, and included a baseline without domain heuristics. The four variants run in clingo. The ground Alpha-like version simulates that reading with transformations such as bound-guarded unrolling. Those transformations have limits. On HRP, for example, the ground simulation drops some capacity guards, so it can suggest different choices from the lazy version. I also use the Alpha solver itself as an external comparison.

## 8. BSP search drops to 120 choices

**Da proiettare.** Grafico BSP delle scelte per dimensione e dato a n = 120.

**Da dire.** The baseline and lazy clingo-like choice counts agree because the lazy clingo-like heuristic finds no applicable candidates during search on this encoding. The Alpha-like variant can guide the solver while the targets are still free, reaching a solution in one hundred and twenty choices with no conflicts. Solving takes about four hundredths of a second, but grounding still takes around one hundred and fifty-four seconds. The base program remains a major cost in this BSP encoding.

## 9. PUP uses nearly half the time and memory

**Da proiettare.** Grafico della memoria al crescere di N e confronto su double-200, entrambi Alpha-like. Tempo interno 438.6 e 224.0 s. Picco di memoria 24.4 e 12.7 GB.

**Da dire.** The Partner Units Problem allocates zones and sensors to units under capacity and connectivity constraints. The unguided baseline reaches size eighty. Both Alpha-like variants solve the published suite through size two hundred. On that largest instance, lazy evaluation brings total clingo time down to about two hundred and twenty-four seconds and peak memory to twelve point seven gigabytes. Most of the difference in runtime comes from grounding.

## 10. Where does heuristic laziness pay off?

**Da proiettare.** BSP, grounding del programma. PUP, costo dell’euristica ground. HRP, costo della singola decisione.

**Da dire.** The most important cost varies across these problems. On BSP, the grounding of the base encoding can dominate. On PUP, heuristic laziness saves time and memory on the same solved instance. On the largest House Reconfiguration instance, the embedded Prolog backend spends roughly ninety-four percent of its time inside the propagator. This shows why we measured the work per decision as well as the number of decisions. My contribution is a way to evaluate a declarative heuristic on the current search state within clingo’s ground-and-solve architecture.

### Per le domande

- BSP compatto, tab. 5.12. A n = 200, baseline 604 regole, lazy Alpha-like 606, ground Alpha-like 8,101,503.
- Ranking, §§3.1.3–3.1.4. Il campo a 16 bit di clasp può saturare e cancellare distinzioni tra pesi.
- Alpha, §5.9. Su double-200 ha memoria di picco simile a lazy C++ e tempo inferiore. Su house-20 lazy C++ è più veloce delle configurazioni Alpha testate.
- Protocollo, §6.2. Una esecuzione per configurazione e istanza.


