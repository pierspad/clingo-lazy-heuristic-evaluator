% ============================================
% Definizione del dominio come definito nel paper di alpha
% il range è definito in :
% instances/BSP_instances/BSP_range.lp

x(1..n).
heuristic_base(Base) :- Base = n + 1.

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB - SC)**2 > 1.

% euristiche lazy query-driven tramite predicati ausiliari
h_b(X,S) :- x(X), not c(X), S = #sum{Y : c(Y)}.
h_c(X,S) :- x(X), not b(X), S = #sum{Y : b(Y)}.

% query-driven lazy heuristics, alpha-like default negation
heuristic(alpha, "heuristic(b(X), W, 0, true) :- holds(h_b(X,S)), holds(heuristic_base(Base)), target_available(b(X)), W is Base*S+X.").
heuristic(alpha, "heuristic(c(X), W, 0, true) :- holds(h_c(X,S)), holds(heuristic_base(Base)), target_available(c(X)), W is Base*S+X.").
