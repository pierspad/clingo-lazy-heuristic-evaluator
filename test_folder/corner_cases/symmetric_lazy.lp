#const n=4.

dom(1..n).
1 { choose(X) : dom(X) } 1.

__heuristic(__target(choose), dom, __weight(1), __priority(1), true).

#show choose/1.
