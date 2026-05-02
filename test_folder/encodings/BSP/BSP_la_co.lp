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

% L'ordine degli argomenti è irrilevante: il target è marcato da __target/1.
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c, 0)), __weight(self), __priority(s), true).
__heuristic(__target(c), x, __n_b, __bind(s, __sum(b, 0)), __weight(self), __priority(s), true).
