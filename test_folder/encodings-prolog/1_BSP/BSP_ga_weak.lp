% ============================================
% Alpha semantics ground-and-solve per BSP.
% il range è definito in :
% instances/BSP_instances/BSP_range.lp

x(1..n).

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
sumC(Sum) :- Sum = #sum{Y : c(Y)}.
sumB(Sum) :- Sum = #sum{Y : b(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB - SC)**2 > 1.

% heuristics
#heuristic b(X) : x(X), S = #sum{Y : c(Y)}. [(((n+1)*S)+X), true]
#heuristic c(X) : x(X), S = #sum{Y : b(Y)}. [(((n+1)*S)+X), true]
