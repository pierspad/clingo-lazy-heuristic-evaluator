% ============================================
% BSP con Lazy Grounding delle euristiche
% ============================================
% Questa codifica usa __heuristic/N (template flessibile)
% con il sistema di binding variabili ed espressioni AST.
%
% Il propagatore HeuristicPropagator legge i template
% e genera dinamicamente le istanze euristiche
% durante la BCP quando i body literal diventano veri.
%
% Formato __heuristic/N:
%   - 1° argomento: predicato target (fisso)
%   - Successivi (ordine libero):
%     * atomo semplice        → body positivo (es. x)
%     * __n_<pred>            → body negativo (es. __n_c → not c(X))
%     * __bind(var, __agg(p)) → binding variabile → aggregato
%     * __weight(expr)        → espressione per il peso
%     * __priority(expr)      → espressione per la priorità
%     * true/false/sign       → segno dell'euristica
%
% Espressioni supportate:
%     * numero intero          → costante
%     * self                   → valore del dominio
%     * variabile (da __bind)  → valore corrente dell'aggregato
%     * __add(a, b)            → somma
%     * __sub(a, b)            → sottrazione
%     * __mul(a, b)            → moltiplicazione
% ============================================

% il range è definito in
% __.BSP_range.lp

x(1..n).

#const tot = (n*(n+1))/2.
#const min_val = (tot-1)/2.
#const max_val = (tot+1)/2.

% Guess
1 { b(X); c(X) } 1 :- x(X).

% Check lineare equivalente al vincolo sulla differenza tra le somme.
:- not min_val <= #sum{ Y : b(Y) } <= max_val.


% ============================================
% TEMPLATE EURISTICI (solo 2 fatti ground!)
% ============================================
%
% Queste 2 regole sostituiscono le O(n) regole __heuristic/4:
%   __heuristic(b(X),X,__sum(c),true) :- x(X), not c(X).
%   __heuristic(c(X),X,__sum(b),true) :- x(X), not b(X).
%
% Equivalente nativo:
%   #heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]
%   #heuristic c(X) : x(X), not b(X), S = #sum{Y : b(Y)}. [X@S, true]
%
% L'ordine degli argomenti (dopo il primo) è irrilevante.

__heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).
__heuristic(c, x, __n_b, __bind(s, __sum(b)), __weight(self), __priority(s), true).
