
%%% initial assignment

assigned_zone_unit(1,1).


%%% assign zones

assignable_zone_unit(Z,U)   :- zone2sensor(Z,S), assigned_sensor_unit(S,U).
assignable_zone_unit(Z,U-1) :- zone2sensor(Z,S), assigned_sensor_unit(S,U), comUnit(U-1).
assignable_zone_unit(Z,U+1) :- zone2sensor(Z,S), assigned_sensor_unit(S,U), comUnit(U+1).

zone_blocked_on_unit(Z,UZ) :- assigned_sensor_unit(S,US), zone2sensor(Z,S),
    comUnit(UZ), |US-UZ| > 1.

zone_blocked_on_unit(Z,UZ) :- assigned_zone_unit(Z1,UZ1), zone2sensor(Z,S),
    zone2sensor(Z1,S), comUnit(UZ), |UZ-UZ1| > 2.

zone_blocked_on_unit(Z,U) :- zone2sensor(Z,_), comUnit(U),
    2 <= #count{Z1: assigned_zone_unit(Z1,U), Z1 != Z}.
zone_blocked_on_unit(Z,U) :- assigned_zone_unit(Z,U1), comUnit(U), U1 != U.

%%% zone choice

assigned_zone_unit(Z,U)     :- assignable_zone_unit(Z,U), not not_assigned_zone_unit(Z,U), 0 < U.
not_assigned_zone_unit(Z,U) :- assignable_zone_unit(Z,U), not assigned_zone_unit(Z,U), 0 < U.
not_assigned_zone_unit(Z,U) :- zone_blocked_on_unit(Z,U).


%%% assign sensors

assignable_sensor_unit(S,U)   :- zone2sensor(Z,S), assigned_zone_unit(Z,U).
assignable_sensor_unit(S,U-1) :- zone2sensor(Z,S), assigned_zone_unit(Z,U), comUnit(U-1).
assignable_sensor_unit(S,U+1) :- zone2sensor(Z,S), assigned_zone_unit(Z,U), comUnit(U+1).

sensor_blocked_on_unit(S,US) :- assigned_zone_unit(Z,UZ), zone2sensor(Z,S),
    comUnit(US), |UZ-US| > 1.

sensor_blocked_on_unit(S,US) :- assigned_sensor_unit(S1,US1), zone2sensor(Z,S),
    zone2sensor(Z,S1), comUnit(US), |US-US1| > 2.

sensor_blocked_on_unit(S,U) :- zone2sensor(_,S), comUnit(U),
    2 <= #count{S1: assigned_sensor_unit(S1,U), S1 != S}.
sensor_blocked_on_unit(S,U) :- assigned_sensor_unit(S,U1), comUnit(U), U1 != U.

%%% sensor choice

assigned_sensor_unit(S,U)     :- assignable_sensor_unit(S,U), not not_assigned_sensor_unit(S,U), 0 < U.
not_assigned_sensor_unit(S,U) :- assignable_sensor_unit(S,U), not assigned_sensor_unit(S,U), 0 < U.
not_assigned_sensor_unit(S,U) :- sensor_blocked_on_unit(S,U).


assigned_zone(Z)   :- assigned_zone_unit(Z,U).
assigned_sensor(S) :- assigned_sensor_unit(S,U).

%%% constraints

:- zone2sensor(Z,_), not assigned_zone(Z).
:- zone2sensor(_,S), not assigned_sensor(S).

:- zone2sensor(Z,S), assigned_sensor_unit(S,U1), assigned_zone_unit(Z,U2), |U1-U2| > 1.

#show assigned_zone_unit/2.
#show assigned_sensor_unit/2.
