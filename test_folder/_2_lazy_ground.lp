% ============================================
% BSP con Lazy Grounding delle euristiche
% ============================================
% Questa codifica usa __heuristic/N (template flessibile)
% al posto di __heuristic/4 (istanziato da Gringo).
%
% Il propagatore HeuristicPropagator legge i template
% e genera dinamicamente le istanze euristiche
% durante la BCP quando i body literal diventano veri.
%
% Formato __heuristic/N:
%   - 1° argomento: predicato target (fisso)
%   - Successivi (ordine libero):
%     * atomo semplice  → body positivo (es. x)
%     * __n_<pred>      → body negativo (es. __n_c → not c(X))
%     * self            → weight = valore del dominio
%     * numero          → weight costante
%     * __sum(p), etc.  → aggregato per la priority
%     * __w_sum(p), etc. → aggregato per il weight
%     * true/false/sign → segno dell'euristica
% ============================================

% il range è definito in
% __.common_range.lp

x(1..n).

% Guess
1 { b(X); c(X) } 1 :- x(X).

% Calcolo delle somme
sumB(Sum) :- Sum = #sum{Y : b(Y)}.
sumC(Sum) :- Sum = #sum{Y : c(Y)}.

% Check
:- sumB(SB), sumC(SC), (SB-SC)**2 > 1.


% ============================================
% TEMPLATE EURISTICI (solo 2 fatti ground!)
% ============================================
%
% Queste 2 regole sostituiscono le O(n) regole __heuristic/4:
%   __heuristic(b(X),X,__sum(c),true) :- x(X), not c(X).
%   __heuristic(c(X),X,__sum(b),true) :- x(X), not b(X).
%
% #heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]
% #heuristic c(X) : x(X), not b(X), S = #sum{Y : b(Y)}. [X@S, true]
%
% L'ordine degli argomenti (dopo il primo) è irrilevante:
%   __heuristic(b, __n_c, x, self, __sum(c), true).
% è equivalente a:
%   __heuristic(b, x, __n_c, self, __sum(c), true).

__heuristic(b, x, __n_c, self, __sum(c), true).
__heuristic(c, x, __n_b, self, __sum(b), true).
