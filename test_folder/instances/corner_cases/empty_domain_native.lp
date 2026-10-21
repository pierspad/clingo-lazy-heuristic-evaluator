#const n=0.

dom(1..n).
{ choose(X) } :- dom(X).

#heuristic choose(X) : dom(X). [X,true]

#show choose/1.
