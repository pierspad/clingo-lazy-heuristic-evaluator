% il range è definito in 
% __.common_range.lp

% Guess
1 { b(X); c(X) } 1 :- x(X).

% Calcolo delle somme
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% Check
:- sumB(SB), sumC(SC), (SB-SC)**2 > 1.


% euristiche di dominio. 
% quelle originali sono queste
% #heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]
% #heuristic c(X) : x(X), not b(X), S = #sum{Y : b(Y)}. [X@S, true]

% le riscriviamo come:
__heuristic(b(X),X,S,true) :- x(X), not c(X), S = __dyn_sum(c).
__heuristic(c(X),X,S,true) :- x(X), not b(X), S = __dyn_sum(b).

