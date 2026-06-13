% ============================================
% BSP - LAZY, backend NATIVE, semantica CLINGO (lc).
% Equivalente nativo di encodings-prolog/1_BSP/BSP_lc.lp.
% Differenze da BSP_la.lp: __semantics(clingo) ->
%   - __n_c (not c) richiede che c(X) sia FALSO (non solo indeciso);
%   - l'aggregato __sum(c) si attiva solo a sorgenti completamente determinate.
% W is (n+1)*S + X. Esegui con: --heuristic=Domain
% ============================================

x(1..n).

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB - SC)**2 > 1.

% heuristics (DSL nativo, semantica clingo)
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)),
            __weight(__add(__mul(s, B), self)), __priority(0),
            __semantics(clingo), __modifier(true)) :- B = n + 1.
__heuristic(__target(c), x, __n_b, __bind(s, __sum(b)),
            __weight(__add(__mul(s, B), self)), __priority(0),
            __semantics(clingo), __modifier(true)) :- B = n + 1.

#show b/1.
#show c/1.
#show sumB/1.
#show sumC/1.
