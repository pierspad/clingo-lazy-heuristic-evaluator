#const n=0.

dom(1..n).
{ choose(X) } :- dom(X).

__heuristic(__target(choose), dom, __weight(self), __priority(1), true).

#show choose/1.
