% ============================================
% BSP - LAZY, backend NATIVE (propagatore C++, fatti __heuristic).
% Equivalente nativo di encodings-prolog/1_BSP/BSP_la.lp.
%
% Le euristiche lazy NON sono stringhe Prolog: sono fatti __heuristic(...)
% letti dal propagatore C++ in init(). L'aggregato Sigma c (risp. Sigma b)
% e' mantenuto in modo incrementale a runtime (__sum), quindi il grounder
% non vede alcun aggregato euristico (niente esplosione combinatoria).
%
% Mappa col file Prolog:
%   aggregate_all(sum(Y), holds(c(Y)), S)  -> __bind(s, __sum(c))   [somma globale di c]
%   alpha_not(c(X))                        -> __n_c  (+ __semantics(alpha))
%   holds(x(X))                            -> x      (corpo positivo implicito, tupla = target)
%   target_available(b(X))                 -> implicito (il propagatore decide solo target liberi)
%   W is (n+1)*S + X                       -> __weight(__add(__mul(s, B), self)), B = n+1
%
% NB: __heuristic e' un FATTO ground: il corpo ASP ":- B = n+1" serve solo a
% far calcolare a gringo la costante Base = n+1 e iniettarla come numero.
% il range (n) e' definito in: instances/BSP_instances/BSP_range.lp
% Esegui con: --heuristic=Domain
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

% heuristics (DSL nativo, semantica alpha)
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)),
            __weight(__add(__mul(s, B), self)), __priority(0),
            __semantics(alpha), __modifier(true)) :- B = n + 1.
__heuristic(__target(c), x, __n_b, __bind(s, __sum(b)),
            __weight(__add(__mul(s, B), self)), __priority(0),
            __semantics(alpha), __modifier(true)) :- B = n + 1.

#show b/1.
#show c/1.
#show sumB/1.
#show sumC/1.
