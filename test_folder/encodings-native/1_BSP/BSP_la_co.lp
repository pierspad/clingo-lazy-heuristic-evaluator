

x(1..n).

#const tot = (n*(n+1))/2.
#const min_val = tot / 2.
#const max_val = (tot + 1) / 2.

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
:- not min_val <= #sum{ Y : b(Y) } <= max_val.

% heuristics (DSL nativo, semantica alpha)
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)),
            __weight(__add(__mul(s, B), self)),
            __semantics(alpha), __modifier(true)) :- B = n + 1.
__heuristic(__target(c), x, __n_b, __bind(s, __sum(b)),
            __weight(__add(__mul(s, B), self)),
            __semantics(alpha), __modifier(true)) :- B = n + 1.

#show b/1.
#show c/1.
