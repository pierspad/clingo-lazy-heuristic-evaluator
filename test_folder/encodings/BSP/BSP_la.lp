% ============================================
% Lazy grounding delle euristiche
% il range è definito in:
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

% TODO: aggiornare il converter BSP per emettere direttamente la sintassi stringa.
% In semantica clingo-like il ranking globale sta in W, mentre @P resta locale.
heuristic(alpha, "heuristic(b(X), W, 0, true) :- x(X), not_c(X), S = #sum { Y : c(Y) }, W = ((n+1)*S)+X.").
heuristic(alpha, "heuristic(c(X), W, 0, true) :- x(X), not_b(X), S = #sum { Y : b(Y) }, W = ((n+1)*S)+X.").
