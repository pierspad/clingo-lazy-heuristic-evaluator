
x(1..n).
heuristic_base(Base) :- Base = n + 1.

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% constrain difference between sums
:- sumB(SB), sumC(SC), (SB - SC)**2 > 1.

% heuristics
% Sotto semantica clingo un aggregato va letto solo quando tutte le sue fonti
% sono assegnate. Nel backend Prolog il gating non e' un builtin del motore: si
% esprime nel corpo della regola, perche' solo l'autore sa quali sotto-goal
% sono dinamici. \+ target_available(P) vale sse nessuna istanza di P e'
% ancora indecisa.
heuristic("heuristic(b(X), W, 0, true) :- \\+ target_available(c(_)), aggregate_all(sum(Y), holds(c(Y)), S), holds(heuristic_base(Base)), holds(x(X)), target_available(b(X)), clingo_not(c(X)), W is Base*S+X.").
heuristic("heuristic(c(X), W, 0, true) :- \\+ target_available(b(_)), aggregate_all(sum(Y), holds(b(Y)), S), holds(heuristic_base(Base)), holds(x(X)), target_available(c(X)), clingo_not(b(X)), W is Base*S+X.").


#show b/1.
#show c/1.
#show sumB/1.
#show sumC/1.
