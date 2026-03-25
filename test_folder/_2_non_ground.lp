% 1. Fatti iniziali e regole di scelta
x(1..3).
{ b(X); c(X) } :- x(X).


% Dichiariamo i target candidati (Caso Non-Ground base)
% #heuristic b(x): x(X), not c(X), S = #sum{Y : c(Y)}, [X@S].
% #heuristic c(x): x(X), not b(X), S = #sum{Y : b(Y)}, [X@S].

% Il peso verrà calcolato dinamicamente dal propagatore C++
__heuristic(b(X)) :- x(X).
