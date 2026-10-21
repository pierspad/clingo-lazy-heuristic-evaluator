
% gc_co = gc + formulazione compatta del vincolo di bilanciamento.
% Le direttive #heuristic restano identiche a BSP_gc.lp: con il programma base
% ridotto a poche centinaia di regole, il grounding misurato e' quello della
% sola componente euristica.

x(1..n).

#const tot = (n*(n+1))/2.
#const min_val = tot / 2.
#const max_val = (tot + 1) / 2.

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
:- not min_val <= #sum{ Y : b(Y) } <= max_val.

% heuristics
#heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}, W = ((n+1)*S)+X. [W, true]
#heuristic c(X) : x(X), not b(X), S = #sum{Y : b(Y)}, W = ((n+1)*S)+X. [W, true]
