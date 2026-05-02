elem(z,Z) :- zone2sensor(Z,D).
elem(s,D) :- zone2sensor(Z,D).

{ assign(U,T,X) } :- elem(T,X), comUnit(U).

:- assign(U,T,X1), assign(U,T,X2), assign(U,T,X3), X1<X2, X2<X3.
:- assign(U1,T,X), assign(U2,T,X), U1<U2.
atLeastOneUnit(T,X):- assign(_,T,X).
:- elem(T,X), not atLeastOneUnit(T,X).

partnerunits(U,P) :- assign(U,z,Z), assign(P,s,D), zone2sensor(Z,D), U!=P.
partnerunits(U,P) :- partnerunits(P,U).
:- partnerunits(U,P1), partnerunits(U,P2), partnerunits(U,P3), P1<P2, P2<P3.
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% breadth-order
cover(Z,z,1) :- Z=#min{K : elem(z,K)}.
cover(Y,s,N+1) :- cover(X,z,N), zone2sensor(X,Y), N<#count{Z,T : elem(T,Z)}.
cover(Y,z,N+1) :- cover(X,s,N), zone2sensor(Y,X), N<#count{Z,T : elem(T,Z)}.

order(X,T,O) :- elem(T,X), O = #min{ L : cover(X,T,L) }.
maxOrder(M) :- M=#max{N : order(_,_,N)}.
maxUnit(M) :- M=#max{N : comUnit(N)}.
maxElem(M) :- M=#max{N : elem(_,N)}.

% assign first zone in the order to the first unit.
#heuristic assign(1,T,X) : order(X,T,1). [1000, true]

% Assign in the order:
% h1: try preceding units first.

% The experiment showed that priorities do not work as expected for ground atoms also. Maybe due to some bug in the implementation.
% Therefore, a hand-crafted formula for computing level weights is used.

h_assign_1(U1,T,X,W) :- order(X,T,O), assign(U,T1,Y), order(Y,T1,O-1), maxOrder(M), maxUnit(MU), comUnit(U1), U1<=U, maxElem(ME), W=10*MU*(M-O)+2*(ME-X)+U1. 

#heuristic assign(U,T,X) : h_assign_1(U,T,X,W). [W, true]

% h2: assign to an unused unit.

% Cannot specify "unused" without NAF or aggregates in the heuristic. Therefore, define an ascending order of units by weights.
% This assumes that all assigned units were already tried by the solver while evaluating the 
% first heuristic and created conflicts will not allow the solver to check make those assignments one more time.
% If the assumption works, then the solver should prefer the first unused unit.

h_assign_2(U+1,T,X,W) :- order(X,T,O), assign(U,T1,Y), order(Y,T1,O-1), maxOrder(M), maxUnit(MU), comUnit(U+1), maxElem(ME), W=10*MU*(M-O)+2*(ME-X).

#heuristic assign(U,T,X) : h_assign_2(U,T,X,W). [W, true]

assigned_zone_unit(Z, U) :- assign(U,z,Z).
assigned_zone_unit(S, U) :- assign(U,s,S).
