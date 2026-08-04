dom(1).
{ choose(X) } :- dom(X).

:- not choose(1).
:- choose(1).

__heuristic(__target(choose), dom, __weight(self), __modifier(true), __semantics(clingo)).

#show choose/1.
