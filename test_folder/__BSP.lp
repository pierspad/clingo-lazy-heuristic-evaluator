% Definizione del dominio
x(1..3).

% Scelta (guessing)
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% Calcolo delle somme
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% Vincolo sulla differenza
:- sumB(SB), sumC(SC), (SB-SC)**2 > 1.

% euristiche di dominio

#heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]
#heuristic c(X) : x(X), not b(X), S = #sum{Y : b(Y)}. [X@S, true]