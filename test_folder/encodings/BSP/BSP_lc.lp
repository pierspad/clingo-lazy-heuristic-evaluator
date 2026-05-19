% ============================================
% Definizione del dominio come definito nel paper di alpha
% il range è definito in :
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

% heuristics
% Originale: #heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [(((n+1)*S)+X), true]
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c, 0)),
            __weight(__add(__mul(__add(n, 1), s), self)), __priority(0), __modifier(true), __semantics(clingo)).
% Originale: #heuristic c(X) : x(X), not b(X), S = #sum{Y : b(Y)}. [(((n+1)*S)+X), true]
__heuristic(__target(c), x, __n_b, __bind(s, __sum(b, 0)),
            __weight(__add(__mul(__add(n, 1), s), self)), __priority(0), __modifier(true), __semantics(clingo)).
