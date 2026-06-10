
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

partnerUnits(UnitID1,UnitID2) :-
    assign(UnitID1,z,ZoneID),
    assign(UnitID2,s,SensorID),
    zone2sensor(ZoneID,SensorID),
    UnitID1 != UnitID2.

partnerUnits(UnitID1,UnitID2) :-
    partnerUnits(UnitID2,UnitID1).

:- partnerUnits(UnitID,Partner1),
   partnerUnits(UnitID,Partner2),
   partnerUnits(UnitID,Partner3),
   Partner1<Partner2,
   Partner2<Partner3.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% breadth-order

% start BFS from the smallest zone id

cover(MinZoneID,z,1) :-
    MinZoneID=#min{ZoneID : elem(z,ZoneID)}.


% from a zone go to connected sensors

cover(SensorID,s,Level+1) :-
    cover(ZoneID,z,Level),
    zone2sensor(ZoneID,SensorID),
    Level<#count{ElementID,Type : elem(Type,ElementID)}.


% from a sensor go to connected zones

cover(ZoneID,z,Level+1) :-
    cover(SensorID,s,Level),
    zone2sensor(ZoneID,SensorID),
    Level<#count{ElementID,Type : elem(Type,ElementID)}.



% convert BFS levels into ordering

elementOrder(ElementID,ElementType,OrderLevel) :-
    elem(ElementType,ElementID),
    OrderLevel=#min{Level : cover(ElementID,ElementType,Level)}.


maxOrder(MaxOrder) :-
    MaxOrder=#max{OrderLevel : elementOrder(_,_,OrderLevel)}.

maxUnit(MaxUnitID) :-
    MaxUnitID=#max{UnitID : comUnit(UnitID)}.

maxElem(MaxElementID) :-
    MaxElementID=#max{ElementID : elem(_,ElementID)}.



% assign first element in BFS order to first unit

#heuristic assign(1,ElementType,ElementID) :
    elementOrder(ElementID,ElementType,1).
    [1000,true]



% h1: prefer previous units first

heuristicAssignPrevious(
    PreferredUnit,
    ElementType,
    ElementID,
    Weight
) :-
    elementOrder(ElementID,ElementType,OrderLevel),
    assign(CurrentUnit,CurrentType,CurrentElement),
    elementOrder(CurrentElement,CurrentType,OrderLevel-1),
    maxOrder(MaxOrder),
    maxUnit(MaxUnit),
    comUnit(PreferredUnit),
    PreferredUnit<=CurrentUnit,
    maxElem(MaxElement),
    Weight=10*MaxUnit*(MaxOrder-OrderLevel)
           +2*(MaxElement-ElementID)
           +PreferredUnit.


#heuristic assign(UnitID,ElementType,ElementID) :
    heuristicAssignPrevious(UnitID,ElementType,ElementID,Weight).
    [Weight,true]



% h2: prefer creating a new unused unit

heuristicAssignNew(
    UnitID+1,
    ElementType,
    ElementID,
    Weight
) :-
    elementOrder(ElementID,ElementType,OrderLevel),
    assign(UnitID,CurrentType,CurrentElement),
    elementOrder(CurrentElement,CurrentType,OrderLevel-1),
    maxOrder(MaxOrder),
    maxUnit(MaxUnit),
    comUnit(UnitID+1),
    maxElem(MaxElement),
    Weight=10*MaxUnit*(MaxOrder-OrderLevel)
           +2*(MaxElement-ElementID).


#heuristic assign(UnitID,ElementType,ElementID) :
    heuristicAssignNew(UnitID,ElementType,ElementID,Weight).
    [Weight,true]

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


assignedZoneUnit(ZoneID,UnitID) :-
    assign(UnitID,z,ZoneID).

assignedZoneUnit(SensorID,UnitID) :-
    assign(UnitID,s,SensorID).