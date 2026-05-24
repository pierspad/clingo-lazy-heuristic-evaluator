% ============================================
% Lazy grounding delle euristiche e vincolo ottimizzato
% il range è definito in:
% instances/BSP_instances/BSP_range.lp

x(1..n).

#const tot = (n*(n+1))/2.
#const min_val = tot / 2.
#const max_val = (tot + 1) / 2.

% Guess
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% Check lineare equivalente al vincolo sulla differenza tra le somme.
:- not min_val <= #sum{ Y : b(Y) } <= max_val.

% query-driven lazy heuristics, alpha-like default negation
heuristic(alpha, "heuristic(b(X), W, 0, true) :- holds(x(X)), default_not(c(X)), aggregate_all(sum(Y), holds(c(Y)), S), aggregate_all(max(Y), holds(x(Y)), N), W is ((N+1)*S)+X, target_available(b(X)).").
heuristic(alpha, "heuristic(c(X), W, 0, true) :- holds(x(X)), default_not(b(X)), aggregate_all(sum(Y), holds(b(Y)), S), aggregate_all(max(Y), holds(x(Y)), N), W is ((N+1)*S)+X, target_available(c(X)).").

#show b/1.
#show c/1.
