
x(1..n).
heuristic_base(Base) :- Base = n + 1.

#const tot = (n*(n+1))/2.
#const min_val = tot / 2.
#const max_val = (tot + 1) / 2.

% Guess
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
:- not min_val <= #sum{ Y : b(Y) } <= max_val.

% heuristics
heuristic("heuristic(b(X), W, 0, true) :- aggregate_all(sum(Y), holds(c(Y)), S), holds(heuristic_base(Base)), holds(x(X)), target_available(b(X)), alpha_not(c(X)), W is Base*S+X.").
heuristic("heuristic(c(X), W, 0, true) :- aggregate_all(sum(Y), holds(b(Y)), S), holds(heuristic_base(Base)), holds(x(X)), target_available(c(X)), alpha_not(b(X)), W is Base*S+X.").

#show b/1.
#show c/1.
