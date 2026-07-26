
x(1..n).

#const tot = (n*(n+1))/2.
sum_value(0..tot).

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB - SC)**2 > 1.

% heuristics
#heuristic b(X) : x(X), sum_value(S), S <= #sum{Y : c(Y)}, W = ((n+1)*S)+X. [W, true]
#heuristic c(X) : x(X), sum_value(S), S <= #sum{Y : b(Y)}, W = ((n+1)*S)+X. [W, true]
