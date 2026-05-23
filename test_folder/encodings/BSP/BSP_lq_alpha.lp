% ============================================
% Query-driven lazy heuristics for BSP, alpha-like negation.
% The range is defined in instances/BSP_instances/BSP_range.lp.

x(1..n).

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB - SC)**2 > 1.

heuristic(alpha, "heuristic(b(X), W, 0, true) :- holds(x(X)), default_not(c(X)), aggregate_all(sum(Y), holds(c(Y)), S), n(N), W is (N + 1) * S + X, target_available(b(X)).").

heuristic(alpha, "heuristic(c(X), W, 0, true) :- holds(x(X)), default_not(b(X)), aggregate_all(sum(Y), holds(b(Y)), S), n(N), W is (N + 1) * S + X, target_available(c(X)).").

#show b/1.
#show c/1.
#show sumB/1.
#show sumC/1.
