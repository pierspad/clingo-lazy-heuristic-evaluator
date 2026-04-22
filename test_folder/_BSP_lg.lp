% ============================================
% Lazy grounding delle euristiche
% il range è definito in:
% BSP_instances/__.BSP_range.lp

x(1..n).

% Guess con la choice rule
1 { b(X); c(X) } 1 :- x(X).


% check solution
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB-SC)**2 > 1.

% L'ordine degli argomenti (dopo il primo) è irrilevante.
__heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).
__heuristic(c, x, __n_b, __bind(s, __sum(b)), __weight(self), __priority(s), true).
