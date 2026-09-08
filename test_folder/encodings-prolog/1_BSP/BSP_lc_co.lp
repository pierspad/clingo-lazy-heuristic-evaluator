
% lc_co = lc + formulazione compatta del vincolo di bilanciamento.
% Coppia controllata di la_co sul backend Prolog: stesso programma ground,
% stesse regole heuristic/1, cambia solo la lettura della negazione
% (clingo_not al posto di alpha_not) piu' il gating dell'aggregato.

x(1..n).
heuristic_base(Base) :- Base = n + 1.

#const tot = (n*(n+1))/2.
#const min_val = tot / 2.
#const max_val = (tot + 1) / 2.

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
:- not min_val <= #sum{ Y : b(Y) } <= max_val.

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
