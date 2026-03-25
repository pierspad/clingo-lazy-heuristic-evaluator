% 1. Fatti iniziali e regole di scelta
a.
{ b; c }.

% 2. Regole logiche standard
d :- b.
e :- c.

% 3. La nostra direttiva euristica custom (Caso Ground)
@heuristic c : a. [1@1, true]