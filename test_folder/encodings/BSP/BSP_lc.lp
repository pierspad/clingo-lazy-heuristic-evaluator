% ============================================
% Definizione del dominio come definito nel paper di alpha
% il range è definito in :
% instances/BSP_instances/BSP_range.lp

x(1..n).

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB - SC)**2 > 1.

% heuristics
% Originale: #heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [(((n+1)*S)+X), true]
% TODO: aggiornare il converter BSP per emettere direttamente la sintassi stringa.
heuristic(clingo, "heuristic(b(X), W, 0, true) :- x(X), not_c(X), S = #sum { Y : c(Y) }, W = ((n+1)*S)+X.").
% Originale: #heuristic c(X) : x(X), not b(X), S = #sum{Y : b(Y)}. [(((n+1)*S)+X), true]
heuristic(clingo, "heuristic(c(X), W, 0, true) :- x(X), not_b(X), S = #sum { Y : b(Y) }, W = ((n+1)*S)+X.").
