% ============================================
% BSP - LAZY, backend NATIVE, semantica ALPHA, dominio ottimizzato "co".
% Equivalente nativo di encodings-prolog/1_BSP/BSP_la_co.lp.
% Stessa euristica di BSP_la.lp (alpha), ma il vincolo sulla differenza
% tra le somme e' espresso linearmente con min_val <= #sum <= max_val.
% W is (n+1)*S + X. Esegui con: --heuristic=Domain
% ============================================

x(1..n).

#const tot = (n*(n+1))/2.
#const min_val = tot / 2.
#const max_val = (tot + 1) / 2.

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check lineare equivalente al vincolo sulla differenza tra le somme.
:- not min_val <= #sum{ Y : b(Y) } <= max_val.

% heuristics (DSL nativo, semantica alpha)
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)),
            __weight(__add(__mul(s, B), self)), __priority(0),
            __semantics(alpha), __modifier(true)) :- B = n + 1.
__heuristic(__target(c), x, __n_b, __bind(s, __sum(b)),
            __weight(__add(__mul(s, B), self)), __priority(0),
            __semantics(alpha), __modifier(true)) :- B = n + 1.

#show b/1.
#show c/1.
