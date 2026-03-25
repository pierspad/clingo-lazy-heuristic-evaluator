% Test per gli aggregati generici: __count, __min, __max
% Usa il range standard definito in __.common_range.lp (x(1..n))

% Guess
1 { b(X); c(X) } 1 :- x(X).

% Check: le somme devono differire al massimo di 1
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.
:- sumB(SB), sumC(SC), (SB-SC)**2 > 1.

% ---- Test __count ----
% "Scegli b(X) con priorità = quanti c sono già veri"
__heuristic(b(X), X, __count(c), true) :- x(X), not c(X).

% ---- Test __max ----
% "Scegli c(X) con priorità = massimo valore di b già vero"
__heuristic(c(X), X, __max(b), true) :- x(X), not b(X).
