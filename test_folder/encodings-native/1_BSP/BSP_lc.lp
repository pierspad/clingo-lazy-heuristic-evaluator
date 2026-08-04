
x(1..n).

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB - SC)**2 > 1.

% heuristics
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)),
            __weight(__add(__mul(s, B), self)),
            __semantics(clingo), __modifier(true)) :- B = n + 1.
__heuristic(__target(c), x, __n_b, __bind(s, __sum(b)),
            __weight(__add(__mul(s, B), self)),
            __semantics(clingo), __modifier(true)) :- B = n + 1.

#show b/1.
#show c/1.
#show sumB/1.
#show sumC/1.
