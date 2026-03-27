% ============================================
% BSP con Lazy Grounding delle euristiche
% ============================================
% Questa codifica usa __heuristic_rule/7 (template)
% al posto di __heuristic/4 (istanziato da Gringo).
%
% Il propagatore HeuristicPropagator legge i template
% e genera dinamicamente le istanze euristiche
% durante la BCP quando i body literal diventano veri.
% ============================================

% il range è definito in
% __.common_range.lp

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
% Formato: __heuristic_rule(RuleID, TargetPred, BodyPred, NegBodyPred,
%                           WeightSource, PrioritySpec, Sign)
%
% Significato di ciascun argomento:
%   - RuleID:       identificatore univoco della regola
%   - TargetPred:   predicato target dell'euristica (es. b → suggerisce b(X))
%   - BodyPred:     predicato positivo del body (es. x → trigger su x(X) vero)
%   - NegBodyPred:  predicato negativo del body (es. c → condiz. not c(X))
%   - WeightSource: "self" = usa il valore X come peso, oppure un intero
%   - PrioritySpec: specifica dell'aggregato (es. __sum(c))
%   - Sign:         segno della decisione (true, false, sign)
%
% Queste 2 regole sostituiscono le O(n) regole __heuristic/4:
%   __heuristic(b(X),X,__sum(c),true) :- x(X), not c(X).
%   __heuristic(c(X),X,__sum(b),true) :- x(X), not b(X).

__heuristic_rule(r1, b, x, c, self, __sum(c), true).
__heuristic_rule(r2, c, x, b, self, __sum(b), true).
