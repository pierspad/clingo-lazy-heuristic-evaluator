dom(1).
{ choose(X) } :- dom(X).

:- not choose(1).
:- choose(1).

#heuristic choose(X) : dom(X). [X@1,true]

#show choose/1.
