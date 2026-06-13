% ============================================
% BSP - LAZY, backend NATIVE, via predicati ausiliari (la_aux).
% Equivalente nativo di encodings-prolog/1_BSP/BSP_la_aux.lp.
% Gli ausiliari h_b(X,S)/h_c(X,S) trasportano la somma S; l'euristica
% nativa li legge con __body(..., __bind_arg(s,1)) e usa S nel peso.
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

% ausiliari query-driven (la somma e' trasportata nel 2o argomento)
h_b(X,S) :- x(X), not c(X), S = #sum{Y : c(Y)}.
h_c(X,S) :- x(X), not b(X), S = #sum{Y : b(Y)}.

% heuristics (DSL nativo): __body lega X (match 0-0) ed estrae S (arg 1)
__heuristic(__target(b), __body(h_b, __match(0,0), __bind_arg(s,1)),
            __weight(__add(__mul(s, B), self)), __priority(0),
            __semantics(alpha), __modifier(true)) :- B = n + 1.
__heuristic(__target(c), __body(h_c, __match(0,0), __bind_arg(s,1)),
            __weight(__add(__mul(s, B), self)), __priority(0),
            __semantics(alpha), __modifier(true)) :- B = n + 1.

#show b/1.
#show c/1.
#show sumB/1.
#show sumC/1.
