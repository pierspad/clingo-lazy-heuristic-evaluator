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

prolog_heuristic(alpha, "candidate(b(X), W, 0, true, alpha) :- holds_pos(x(X)), holds_neg(alpha, c(X)), dyn_sum(holds_pos(c(Y)), Y, S), n_value(N), W is ((N+1)*S)+X, target_available(b(X)).").

prolog_heuristic(alpha, "candidate(c(X), W, 0, true, alpha) :- holds_pos(x(X)), holds_neg(alpha, b(X)), dyn_sum(holds_pos(b(Y)), Y, S), n_value(N), W is ((N+1)*S)+X, target_available(c(X)).").
