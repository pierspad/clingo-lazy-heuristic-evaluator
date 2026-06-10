
elem(z,ZoneID) :- zone2sensor(ZoneID,SensorID).
elem(s,SensorID) :- zone2sensor(ZoneID,SensorID).

{ assign(UnitID,ElementType,ElementID) } :-
    elem(ElementType,ElementID),
    comUnit(UnitID).

% every comUnit can have a maximum of two zones and two sensors
% every zone must be assignet to exactly one comUnit
:- assign(UnitID,ElementType,ElementID1),
   assign(UnitID,ElementType,ElementID2),
   assign(UnitID,ElementType,ElementID3),
   ElementID1<ElementID2,
   ElementID2<ElementID3.

:- assign(UnitID1,ElementType,ElementID),
   assign(UnitID2,ElementType,ElementID),
   UnitID1<UnitID2.

atLeastOneUnit(ElementType,ElementID) :-
    assign(_,ElementType,ElementID).

:- elem(ElementType,ElementID),
   not atLeastOneUnit(ElementType,ElementID).

% if comUnit U handles a zone and comUnit P (P!=U) handles a sensor and
% in the real world the sensor belongs to that zone then we call
% the comUnit as "Partners" 
% no more than 2 partners are allowed
partnerunits(UID1,UID2) :- assign(UID1,z,ZoneID), assign(UID2,s,SensorID), zone2sensor(ZoneID,SensorID), UID1!=UID2.
partnerunits(UID1,UID2) :- partnerunits(UID2,UID1).
:- partnerunits(UID1,UID2), partnerunits(UID1,UID3), partnerunits(UID1,UID4), UID2<UID3, UID3<UID4.


	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% breadth-order
cover(MinZone,z,1) :- MinZone=#min{ZoneID : elem(z,ZoneID)}.
cover(SensorID,s,N+1) :- cover(ZoneID,z,N), zone2sensor(ZoneID,SensorID), N<#count{ElementID,Type : elem(Type,ElementID)}.
cover(ZoneID,z,N+1) :- cover(SensorID,s,N), zone2sensor(ZoneID,SensorID), N<#count{ElementID,Type : elem(Type,ElementID)}.

order(ElementID,Type,OrderLevel) :- elem(Type,ElementID), OrderLevel = #min{ Level : cover(ElementID,Type,Level) }.
maxOrder(M) :- M=#max{OrderLevel : order(_,_,OrderLevel)}.
maxUnit(M) :- M=#max{UID : comUnit(UID)}.
maxElem(M) :- M=#max{ElementID : elem(_,ElementID)}.

% assign first zone in the order to the first unit.
#heuristic assign(1,Type,ElementID) : order(ElementID,Type,1). [1000, true]

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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%





assigned_zone_unit(Z, U) :- assign(U,z,Z).
assigned_zone_unit(S, U) :- assign(U,s,S).
