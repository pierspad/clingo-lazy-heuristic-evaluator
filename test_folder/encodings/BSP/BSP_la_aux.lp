% ============================================
% Definizione del dominio come definito nel paper di alpha
% il range è definito in :
% instances/BSP_instances/BSP_range.lp

x(1..n).
#const k = n + 1.

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB - SC)**2 > 1.

% euristiche riscritte tramite predicati ausiliari
h_b(X,S) :- x(X), not c(X), S = #sum{Y : c(Y)}.
h_c(X,S) :- x(X), not b(X), S = #sum{Y : b(Y)}.

% Originale: #heuristic b(X) : h_b(X,S). [(((n+1)*S)+X), true]
__heuristic(__target(b), __body(h_b, __match(0, 0), __bind_arg(s, 1)),
            __weight(__add(__mul(k, s), self)), __priority(0), __modifier(true), __semantics(alpha)).
% Originale: #heuristic c(X) : h_c(X,S). [(((n+1)*S)+X), true]
__heuristic(__target(c), __body(h_c, __match(0, 0), __bind_arg(s, 1)),
            __weight(__add(__mul(k, s), self)), __priority(0), __modifier(true), __semantics(alpha)).
