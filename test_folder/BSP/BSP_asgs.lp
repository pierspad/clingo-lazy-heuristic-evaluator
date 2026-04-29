% ============================================
% Alpha semantics ground-and-solve per BSP.
% il range e' definito in:
% BSP_instances/BSP_range.lp
%
% Questa variante non usa il propagatore lazy: forza Gringo a generare una
% famiglia di #heuristic native per ogni valore possibile della somma.
% Serve come baseline di testing, non come encoding efficiente.

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

% Alpha ground-and-solve:
% - not c(X) / not b(X) e' emulato ottimisticamente: l'euristica e' presente
%   finche' il target opposto non rende il target corrente non libero.
% - S e' il massimo valore gia' garantito dalla somma degli atomi veri.
%   Poiche' i valori di BSP sono positivi, fra tutte le regole S <= #sum{...}
%   Clingo seleziona quella con priorita' S massima, cioe' la somma corrente.
#heuristic b(X) : x(X), sum_value(S), S <= #sum{Y : c(Y)}. [X@S, true]
#heuristic c(X) : x(X), sum_value(S), S <= #sum{Y : b(Y)}. [X@S, true]
