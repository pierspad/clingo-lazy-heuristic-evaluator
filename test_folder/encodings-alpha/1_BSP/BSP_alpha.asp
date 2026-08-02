%% ============================================================
%% BSP per Alpha (Qh) - PRESO TALE E QUALE dai materiali dei paper.
%%
%% Origine: ALPHA/Evaluation/Motivating_Example/Balanced_Sum_Alpha.asp
%% (supplementary material di "Dynamic Aggregates in Expressive ASP
%% Heuristics for Configuration Problems"). NON e' una traduzione fatta
%% qui: e' l'encoding degli autori, copiato senza modifiche, ed e' questo
%% che rende il confronto con clingo difendibile in tesi.
%%
%% max_Value/1 NON e' definito qui: arriva dall'istanza, che il wrapper
%% programs/alpha-qh-1.0 genera da bsp-NNNN.lp (che per clingo e' un
%% "#const n=N."). Cosi' Alpha e clingo girano sulla STESSA taglia.
%%
%% Da eseguire con -uqh: senza quel flag l'aggregato S = #sum{Y : c(Y)}
%% nel corpo dell'euristica viene valutato staticamente e l'euristica non
%% bilancia nulla (verificato: tutti gli elementi finiscono in b).
%%
%% Nota metodologica per la tesi: la parte di VERIFICA (step_Sum_B/
%% step_Sum_C) e' una somma ricorsiva scritta a mano, non un #sum. E' una
%% scelta degli autori, dovuta al costo dei #sum in Alpha, e va dichiarata
%% quando si confronta il tempo totale con quello degli encoding clingo,
%% che per lo stesso controllo usano un #sum nativo.
%% ============================================================

%The Problem: Values defined in the x predicate are assigned to either 
% b or c. We want the sum of the values in b and c to be roughly the same.

%Without heuristics, this could be done using a constraint, which would
%check if the sum of values of both b and c would be close to each other (as seen below, in the verification part).
%This would, however, inevitably lead to slow and unnecessary backtracking.

%With heuristics, if we could gage the current assignment, and check the current sums of values in b and c, 
%we can prioritize assigning values to either b and c, depending on which sum is lesser.
%This would naturally create a balance between both sums. 
%If we further augment our heuristic to prioritize assigning larger values first, then the final difference
%between both sums would be minimized, and backtracking would rarely occur.

%This was only only partially possible prior to the introduction of dynamic aggregates, as normal aggregates would 
%only return the final value, and thus could not be used during the grounding-solving cycle, where heuristics apply.

%While the heuristics, if b's and c's have no further conditions to be assigned, would always follow the same pattern,
%if we introduce some independent b's or c's the heuristics can of course accommodate them.

%max_Value(20).
x(1..V) :-  max_Value(V).        %Initializing values

b(X) :- x(X), not c(X).     %Exclusive choice between c or b.
c(X) :- x(X), not b(X).

%b(200).     %Already existing b's, creating initial imbalance.
%b(201).

%Heuristic for b's taking into account the current sum of values in c, and the value to be assigned.
#heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [X@S]

%Heuristic for c's mirrors that of b.
#heuristic c(X) : x(X), not b(X), S = #sum{Y : b(Y)}. [X@S]


%Verification
%To verify if our set goal was achieved, we want to introduce a constraint, which would exclude answer 
%sets where the difference between the sums of values are greater than 1. For that, we need to calculate the
%final sum of values for both c and b, and compare them. Normally, this would be done using a simple #sum aggregate.
%But the current implementation of Alpha does not have  a functioning (in terms of runtime) implementation.
%As we know the exact structure of x's, b's and c's, we can just sum up all the values manually using the following encoding.
%Afterwards, the constraint can be checked.


step_Sum_B(0,0).
step_Sum_C(0,0).

step_Sum_B(Previous_sum + N,N) :- step_Sum_B(Previous_sum,N - 1), x(N), b(N).
step_Sum_B(Previous_sum,N) :- step_Sum_B(Previous_sum,N - 1), x(N), not b(N).
step_Sum_C(Previous_sum + N,N) :- step_Sum_C(Previous_sum,N - 1), x(N), c(N).
step_Sum_C(Previous_sum,N) :- step_Sum_C(Previous_sum,N - 1), x(N), not c(N).

sum_B(Sum) :- step_Sum_B(Sum,V), max_Value(V).
sum_C(Sum) :- step_Sum_C(Sum,V), max_Value(V).


:- sum_B(SB) , sum_C(SC), (SB-SC)**2 > 1.
