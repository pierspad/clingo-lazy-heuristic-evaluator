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

% query-driven lazy heuristics, clingo-like default negation
heuristic(clingo, "heuristic(b(X), W, 0, true) :- aggregate_all(sum(Y), holds(c(Y)), S), holds(heuristic_base(Base)), holds(x(X)), target_available(b(X)), default_not(c(X)), W is Base*S+X.").
heuristic(clingo, "heuristic(c(X), W, 0, true) :- aggregate_all(sum(Y), holds(b(Y)), S), holds(heuristic_base(Base)), holds(x(X)), target_available(c(X)), default_not(b(X)), W is Base*S+X.").

#show b/1.
#show c/1.
#show sumB/1.
#show sumC/1.
