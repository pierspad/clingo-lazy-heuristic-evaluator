#const n=0.

dom(1..n).
{ choose(X) } :- dom(X).

#heuristic choose(X) : dom(X). [X@1,true]

#show choose/1.
