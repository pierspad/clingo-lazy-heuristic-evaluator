

a(1..21).
b(10).


c(X) :- a(X), b(Y), (X-Y)**2 < 2.
d(X) :- a(X), b(Y), |X-Y| < 2.


e(X) :- a(X), b(Y), (X-Y)**2 <= 4.
f(X) :- a(X), b(Y), |X-Y| <= 4.


%#show e/1.
#show f/1.