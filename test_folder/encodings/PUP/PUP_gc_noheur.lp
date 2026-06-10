
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


assignedZoneUnit(ZoneID,UnitID) :-
    assign(UnitID,z,ZoneID).

assignedZoneUnit(SensorID,UnitID) :-
    assign(UnitID,s,SensorID).