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

% query-driven lazy heuristics, alpha-like default negation
heuristic(alpha, "heuristic(b(X), X, S, true) :- holds(x(X)), default_not(c(X)), aggregate_all(sum(Y), holds(c(Y)), S), target_available(b(X)).").
heuristic(alpha, "heuristic(c(X), X, S, true) :- holds(x(X)), default_not(b(X)), aggregate_all(sum(Y), holds(b(Y)), S), target_available(c(X)).").

#show b/1.
#show c/1.
#show sumB/1.
#show sumC/1.
