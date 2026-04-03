% Definizione del dominio come definito nel paper di alpha
% il range è definito in 
% __.BSP_range.lp

x(1..n).

#const tot = (n*(n+1))/2.
#const min_val = (tot-1)/2.
#const max_val = (tot+1)/2.

% Guess
1 { b(X); c(X) } 1 :- x(X).

% Check lineare equivalente al vincolo sulla differenza tra le somme.
:- not min_val <= #sum{ Y : b(Y) } <= max_val.

% euristiche di dominio

#heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]
#heuristic c(X) : x(X), not b(X), S = #sum{Y : b(Y)}. [X@S, true]




