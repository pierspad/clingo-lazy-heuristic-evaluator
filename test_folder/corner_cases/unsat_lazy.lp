dom(1).
{ choose(X) } :- dom(X).

:- not choose(1).
:- choose(1).

__heuristic(__target(choose), dom, __weight(self), __priority(1), true).

#show choose/1.
