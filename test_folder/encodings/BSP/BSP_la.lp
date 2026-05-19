% ============================================
% Lazy grounding delle euristiche
% il range è definito in:
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

% In semantica clingo-like il ranking globale sta in W, mentre @P resta locale.
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c, 0)),
            __weight(__add(__mul(__add(n, 1), s), self)), __priority(0), __modifier(true), __semantics(alpha)).
__heuristic(__target(c), x, __n_b, __bind(s, __sum(b, 0)),
            __weight(__add(__mul(__add(n, 1), s), self)), __priority(0), __modifier(true), __semantics(alpha)).
