% ============================================
% Lazy grounding delle euristiche
% il range è definito in:
% BSP_instances/BSP_range.lp

x(1..n).

% Guess con la choice rule
1 { b(X); c(X) } 1 :- x(X).


% check solution
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB-SC)**2 > 1.

% L'ordine degli argomenti è irrilevante: il target è marcato da __target/1.
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c, 0)), __weight(self), __priority(s), true).
__heuristic(__target(c), x, __n_b, __bind(s, __sum(b, 0)), __weight(self), __priority(s), true).
