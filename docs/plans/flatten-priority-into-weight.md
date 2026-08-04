# Plan — Flatten priority into the weight, everywhere

## Context

The suite's convention is that Alpha's absolute levels are folded into the weight
(`W_flat = W + P*M`), leaving the priority field only clingo's local per-atom role. This
change finishes that convention: **the weight becomes the single ranking criterion**,
globally and per target, under both semantics, and the priority is removed from the
language, from both backends, and from every encoding.

Decisions taken by the author, binding on this plan:

1. The change may alter search behaviour. The author will re-run the full cluster campaign
   afterwards. Divergence is therefore **reported, not blocking**.
2. `__priority` is removed from the native DSL entirely — the parser must reject it.
3. The Prolog backend drops to `heuristic/3`; the priority argument disappears.

Verified facts this plan rests on (checked in the sources, not assumed):

- Native parser default is already `priority = 0`
  (`clingo-native/libclingo/clingo/heuristic_types.hh:185`).
- `__priority(1)` occurs **only** in HRP: 9 native rules in `HRP_la.lp`, 9 in `HRP_lc.lp`,
  and the corresponding 18 Prolog rule strings. BSP and PUP are `0` everywhere.
- The ground encodings never write `@P` (`[W, true]` / `[1, false]`), so there is nothing
  to remove on the `gc`/`ga` side. **They must not be touched.**
- **The two builds do not share the propagator source.**
  - `clingo-native/libclingo/src/heuristic_propagator.cc` (1294 lines) resolves several
    directives on one target with `update_best_by_local_priority` (line 773): it compares
    `local_priority`, then `candidate_id`. **The weight is never consulted.** This is the
    defect this plan fixes.
  - `clingo-prolog/libclingo/src/heuristic_propagator.cc` (1110 lines) has no such
    function; it uses `ranked_candidate_beats_best` (line 640), `(priority, weight,
    rule_index)` — the weight is already consulted.
- Native global ranking is already weight-driven: the clingo path sets
  `decision_priority = 0`, `decision_weight = level.value` (lines 886-891). Only the
  per-target arbitration is priority-driven.
- HRP's five levels appear already flattened into the weight (`k*LM` for k in 1..4,
  closing level weight 1, `LM = MC + MR + 10` exceeding every intra-level weight).
  Task 4 verifies this against the Alpha original rather than assuming it.

## Global Constraints

- **The heuristic must never change the answer sets.** `tools/check_equivalence.py` must
  pass after every task that touches encodings or a propagator. This is the one hard gate;
  a failure here is a STOP.
- Changes in search behaviour (`choices`, `conflicts`) are permitted and expected, but must
  be **measured and reported** in a before/after table. Never silently absorbed.
- Both builds must keep compiling and both must keep passing their tests.
- Ground encodings (`*_gc.lp`, `*_ga.lp`, `*_ga_weak.lp`, `*_gc_noheur.lp`) are
  **out of scope** — do not touch them.
- The working tree carries ~680 unrelated modified files (graphs, thesis). **Stage only the
  files your task touches.** Never `git add -A`, never `git clean` (`ALPHA/` is untracked
  and is the only copy of that fork on disk).
- Match the surrounding code style, including the Italian comments in the propagator
  sources.

## Task 1 — Capture the pre-change baseline

Before any code changes. Run the short local benchmark and record, for every problem
(BSP, PUP, HRP) and every lazy variant (`la`, `lc`) on both backends, the `choices` and
`conflicts` counts, plus the equivalence-harness result. Write the table to
`.superpowers/sdd/flatten-priority-into-weight/baseline.md`.

This is measurement only: **change no source file.** If the local benchmark cannot be run,
say so explicitly in the report rather than inventing numbers — Task 6 will then compare
against whatever reference is available.

## Task 2 — Native side: remove the priority from the DSL and rank by weight

`clingo-native/libclingo/` — parser, types, propagator, tests, and the native lazy
encodings, as one coherent change.

- Parser (`src/heuristic_parser.cc`): `__priority(...)` is no longer a valid argument and
  must be rejected with a clear message, in the style of the existing validation errors.
- Types (`clingo/heuristic_types.hh`): drop `local_priority_expr` and every priority field
  that becomes dead (`decision_priority`, `ranked_priority`, the priority component of
  `DecisionRankKey`, `ResolvedModifierValue::local_priority`, …). Remove them; do not leave
  fields that are written and never read.
- Propagator (`src/heuristic_propagator.cc`): the candidate that claims a target's `level`
  and `sign` slots is the one with the **greatest weight** (`effect.bias`), ties broken
  deterministically by `candidate_id`. Note that `update_best_by_local_priority` currently
  stores `value`, which for the `sign` slot is `+1`/`-1` and not a weight — the ranking key
  must become a parameter distinct from the stored value. Under **both** semantics the
  global rank is the weight alone. The ranked-set admission gate
  `(decision_priority > 0 || decision_weight > 0)` becomes a weight-only test.
- Native lazy encodings (`test_folder/encodings-native/{1_BSP,2_PUP,3_HRP}/*_l*.lp`):
  delete every `__priority(...)` argument. Weights are not touched in this task.
- C++ unit tests: the suite currently pins the old behaviour (it covers "the
  local-versus-global reading of priorities in the two semantics"). Rewrite those cases to
  pin the new contract — greatest weight wins the target under both semantics — and add a
  case asserting that `__priority(...)` is now rejected by the parser.

Check whether `clingo-prolog`'s copy of the propagator needs a mirror change. Per the
verified facts it already ranks by weight, so the expected answer is "only the priority
field removal, no ranking change" — confirm in the source, do not assume.

Verification: both builds compile; the native C++ test suite passes; `check_equivalence.py`
passes.

## Task 3 — Prolog side: `heuristic/4` becomes `heuristic/3`

- `clingo-prolog/libclingo/src/swi_prolog_heuristic_backend.cc`: the head is read at
  ~line 387 (`PL_get_integer(av + 2, &priority)`). Drop the priority argument; the modifier
  moves from position 3 to position 2.
- The generated runtime program and the `heuristic(T, W, P, M)` query must follow.
- `ranked_candidate_better` / `ranked_candidate_beats_best`
  (`clingo-prolog/libclingo/src/heuristic_propagator.cc:623-648`): both currently compare
  `active.priority` **before** `active.weight`. Deleting the priority *field* is not
  enough — the priority comparison itself must go, so the ordering becomes weight, then
  the existing deterministic tie-break. (Confirmed in Task 2: this copy carries no native
  `__heuristic` path at all, only a dead `HeuristicRuleTemplate` definition, so nothing
  else in it was touched.)
- All Prolog rule strings in `test_folder/encodings-prolog/**` become
  `heuristic(Target, W, Modifier) :- ...`. The `prolog_heuristic/1` alias for the wrapper
  fact stays accepted.
- A rule still written with four arguments must fail loudly, not silently — the silent
  fallback described in the thesis is exactly the failure mode to avoid.

Verification: the Prolog build compiles; a BSP and an HRP run with
`LAZY_HEURISTIC_BACKEND=prolog` report `decide_calls > 0`; `check_equivalence.py` passes.

## Task 4 — Verify (and only if wrong, correct) the HRP weight flattening

Compare `test_folder/encodings-native/3_HRP/HRP_{la,lc}.lp` and their Prolog counterparts
against the original Alpha HRP encoding under `ALPHA/`. Confirm that every `[W@P]` of the
original maps to `W + P*LM`, with `LM` strictly greater than every intra-level weight at
that level. Report the mapping level by level in the report file.

Rewrite a weight **only** if a level is genuinely misplaced. Do not "improve" weights that
already satisfy the rule. If everything is already correct, say so — that is a valid and
expected outcome.

## Task 5 — Documentation

`docs/euristiche-native-sintassi.md` and `docs/euristiche-prolog-sintassi.md` document
`__priority` (§8, §12, §14 of the native doc) and the four-argument Prolog head. Bring both
in line with the implemented syntax, including every example that carries a priority.

Two consequences of Task 2 that the docs must now state, because neither is visible at the
call site:

- The decision-queue admission gate is `weight > 0` alone. `__weight` still defaults to 0
  when absent, so a rule with no `__weight` — or with `__weight(0)` — is now a complete
  no-op. Previously `__priority(1)` by itself was enough to get a target ranked.
- When several rules claim the same target, the winner is the one with the greatest
  weight, ties broken by declaration order. This replaces the old priority-then-declaration
  rule, and it now holds identically under both semantics.

## Task 6 — Rebuild, test, and report the behavioural delta

Rebuild both binaries from scratch, run the C++ unit tests, run
`tools/check_equivalence.py`, and re-run the short benchmark used in Task 1. Produce a
before/after table of `choices` and `conflicts` for `la` and `lc` on all three problems and
both backends, against `baseline.md`.

`check_equivalence.py` failing is a STOP. A behavioural delta is not — report it clearly,
per problem and per variant, so the author knows what the cluster re-run will show.

## Task 7 — Thesis text

Bring `thesis/Tesi_Lazy_Heuristics/` in line with the implemented system:

- `2 - Metodologia.tex`: the flattening subsection (note the author has been editing it
  live — read the current file, and mind the sentence ending "…the same in every variant:"
  whose list has been removed and which now dangles), the "Priority, modifier and
  semantics" paragraph, and the priority row of the translation table.
- `3 - Implementazione.tex`: the per-target resolution and global ranking paragraphs, the
  Prolog rule-string example and its head arity, and the unit-test list in the correctness
  subsection.
- `4 - Risultati.tex`: any sentence referring to the local-versus-global reading of
  priorities.

The document must build: `latexmk -pdf -shell-escape -interaction=nonstopmode`. Do not
change any reported number.
