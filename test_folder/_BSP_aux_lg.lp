% ============================================
% Definizione del dominio come definito nel paper di alpha
% il range è definito in :
% BSP_instances/__.BSP_range.lp

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
% Originale: #heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]
__h_b_1_lazy(X) :- x(X), not c(X).
__heuristic(__target(b), __h_b_1_lazy, __bind(s, __sum(c, 0)), __weight(self), __priority(s), true).
% Originale: #heuristic c(X) : x(X), not b(X), S = #sum{Y : b(Y)}. [X@S, true]
__h_c_2_lazy(X) :- x(X), not b(X).
__heuristic(__target(c), __h_c_2_lazy, __bind(s, __sum(b, 0)), __weight(self), __priority(s), true).


