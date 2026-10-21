
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


%%% auxiliary predicates for heuristics

sensorNumbers(0..2).

num_sensors_on_unit(N,U) :- comUnit(U), sensorNumbers(N),
    N <= #count{S1: assigned_sensor_unit(S1,U)}.
num_sensors_on_unit(2,0).

num_forbidden_places_of_sensors(S,N+N1+N2) :- assignable_sensor_unit(S,_),
    zone2sensor(Z,S), assigned_zone_unit(Z,U),
    num_sensors_on_unit(N,U), num_sensors_on_unit(N1,U-1), num_sensors_on_unit(N2,U+1), U > 1.

num_forbidden_places_of_sensors(S,N+2+N2) :- assignable_sensor_unit(S,_),
    zone2sensor(Z,S), assigned_zone_unit(Z,U),
    num_sensors_on_unit(N,U), num_sensors_on_unit(N2,U+1), U = 1.

num_forbidden_places_of_sensors(S,N+N1+2) :- assignable_sensor_unit(S,_),
    zone2sensor(Z1,S), zone2sensor(Z2,S),
    assigned_zone_unit(Z1,U), assigned_zone_unit(Z2,U+1),
    num_sensors_on_unit(N,U),
    num_sensors_on_unit(N1,U+1).

num_forbidden_places_of_sensors(S,N1+4) :- assignable_sensor_unit(S,_),
    zone2sensor(Z,S), zone2sensor(Z2,S),
    assigned_zone_unit(Z,U), assigned_zone_unit(Z2,U+2),
    num_sensors_on_unit(N1,U+1).

%%% constraints

:- zone2sensor(Z,_), not assigned_zone(Z).
:- zone2sensor(_,S), not assigned_sensor(S).

:- zone2sensor(Z,S), assigned_sensor_unit(S,U1), assigned_zone_unit(Z,U2), |U1-U2| > 1.


%%% heuristics

% Gating clingo degli aggregati: la guardia elenca solo i predicati DINAMICI
% letti dagli aggregati di questa regola (zone2sensor e comUnit sono statici e
% non vanno gated). Vedi la nota equivalente in BSP_lc.lp.
heuristic("heuristic(assigned_sensor_unit(S,U), W, 0, true) :- \\+ target_available(assigned_zone_unit(_,_)), \\+ target_available(assigned_sensor_unit(_,_)), \\+ target_available(num_forbidden_places_of_sensors(_,_)), holds(assignable_sensor_unit(S,U)), target_available(assigned_sensor_unit(S,U)), clingo_not(not_assigned_sensor_unit(S,U)), aggregate_all(count, (holds(zone2sensor(Z,S)), holds(assigned_zone_unit(Z,_))), Deg), dyn_max(holds(num_forbidden_places_of_sensors(S,N)), N, Forb), aggregate_all(count, holds(assigned_sensor_unit(SN,U)), Cnt), aggregate_all(count, (holds(assigned_zone_unit(Z1,U)), holds(zone2sensor(Z1,S))), Direct), W is Deg*10000 + Forb*1000 + Cnt*100 + Direct*10.").

heuristic("heuristic(assigned_zone_unit(Z,U), W, 0, true) :- \\+ target_available(assigned_zone_unit(_,_)), \\+ target_available(num_sensors_on_unit(_,_)), holds(assignable_zone_unit(Z,U)), target_available(assigned_zone_unit(Z,U)), clingo_not(not_assigned_zone_unit(Z,U)), aggregate_all(count, holds(assigned_zone_unit(ZN,U)), A), U1 is U - 1, U2 is U + 1, dyn_max(holds(num_sensors_on_unit(N0,U)), N0, M0), dyn_max(holds(num_sensors_on_unit(N1,U1)), N1, M1), dyn_max(holds(num_sensors_on_unit(N2,U2)), N2, M2), Avail is 6 - (M0 + M1 + M2), W is A*10 + Avail + 100000.").

#show assigned_zone_unit/2.
#show assigned_sensor_unit/2.
