% ============================================
% Lazy grounding delle euristiche e vincolo ottimizzato
% il range è definito in:
% BSP_instances/__.BSP_range.lp

x(1..n).

#const tot = (n*(n+1))/2.
#const min_val = tot / 2.
#const max_val = (tot + 1) / 2.


% Guess
1 { b(X); c(X) } 1 :- x(X).

% Check lineare equivalente al vincolo sulla differenza tra le somme.
:- not min_val <= #sum{ Y : b(Y) } <= max_val.

% L'ordine degli argomenti (dopo il primo) è irrilevante.
__heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).
__heuristic(c, x, __n_b, __bind(s, __sum(b)), __weight(self), __priority(s), true).
