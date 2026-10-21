
% ga_weak_co = ga_weak + formulazione compatta del vincolo di bilanciamento.
% Le direttive restano quelle di BSP_ga_weak.lp: guardie negative rimosse,
% binding di uguaglianza sull'aggregato mantenuto (senza unrolling).

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
#heuristic b(X) : x(X), S = #sum{Y : c(Y)}, W = ((n+1)*S)+X. [W, true]
#heuristic c(X) : x(X), S = #sum{Y : b(Y)}, W = ((n+1)*S)+X. [W, true]
