
% ga_co = ga + formulazione compatta del vincolo di bilanciamento.
% sum_value/1 e le direttive a bound monotoni restano identiche a BSP_ga.lp:
% tolto il programma base, cio' che resta a groundare e' l'unrolling Theta(n^3)
% delle direttive, che e' esattamente cio' che l'esperimento vuole isolare.

x(1..n).

#const tot = (n*(n+1))/2.
#const min_val = tot / 2.
#const max_val = (tot + 1) / 2.

sum_value(0..tot).

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
:- not min_val <= #sum{ Y : b(Y) } <= max_val.

% heuristics
#heuristic b(X) : x(X), sum_value(S), S <= #sum{Y : c(Y)}, W = ((n+1)*S)+X. [W, true]
#heuristic c(X) : x(X), sum_value(S), S <= #sum{Y : b(Y)}, W = ((n+1)*S)+X. [W, true]
