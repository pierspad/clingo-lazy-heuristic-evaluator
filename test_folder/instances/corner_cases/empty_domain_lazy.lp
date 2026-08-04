#const n=0.

dom(1..n).
{ choose(X) } :- dom(X).

__heuristic(__target(choose), dom, __weight(self), __modifier(true), __semantics(clingo)).

#show choose/1.
