
% gc_noheur_co = gc_noheur + formulazione compatta del vincolo di bilanciamento.
% Unica differenza rispetto a BSP_gc_noheur.lp: il check quadratico su sumB/sumC
% e' sostituito dall'intervallo a bound costanti gia' usato da la_co. I due
% vincoli sono equivalenti (SB+SC = tot, quindi |SB-SC| <= 1 sse
% min_val <= SB <= max_val, sia per tot pari che dispari).

x(1..n).

#const tot = (n*(n+1))/2.
#const min_val = tot / 2.
#const max_val = (tot + 1) / 2.

% guessing
b(X) :- x(X), not c(X).
c(X) :- x(X), not b(X).

% check solution
:- not min_val <= #sum{ Y : b(Y) } <= max_val.
