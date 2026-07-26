
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



%%% ausiliari per i join degli aggregati nativi (derivati, non mostrati)

sensor_assigned_zone(S,Z)  :- zone2sensor(Z,S), assigned_zone_unit(Z,_).
sensor_zone_on_unit(S,U,Z) :- zone2sensor(Z,S), assigned_zone_unit(Z,U).

%%% heuristics

__heuristic(__target(assigned_sensor_unit),
            assignable_sensor_unit,
            __n_not_assigned_sensor_unit,
            __bind(deg,    __count(sensor_assigned_zone, 0, __filter(0,0))),
            __bind(forb,   __max(num_forbidden_places_of_sensors, 1, __filter(0,0))),
            __bind(cnt,    __count(assigned_sensor_unit, 1, __filter(1,1))),
            __bind(direct, __count(sensor_zone_on_unit, 0, __filter(0,0), __filter(1,1))),
            __weight(__add(__add(__add(__mul(deg,10000), __mul(forb,1000)),
                                 __mul(cnt,100)), __mul(direct,10))),
            __priority(0), __semantics(alpha), __modifier(true)).
__heuristic(__target(assigned_zone_unit),
            assignable_zone_unit,
            __n_not_assigned_zone_unit,
            __bind(a,  __count(assigned_zone_unit, 1, __filter(1,1))),
            __bind(m0, __max(num_sensors_on_unit, 0, __filter(1,1))),
            __bind(m1, __max(num_sensors_on_unit, 0, __filter(1,1,-1))),
            __bind(m2, __max(num_sensors_on_unit, 0, __filter(1,1,1))),
            __weight(__add(__sub(__sub(__sub(__add(__mul(a,10), 6), m0), m1), m2), 100000)),
            __priority(0), __semantics(alpha), __modifier(true)).

#show assigned_zone_unit/2.
#show assigned_sensor_unit/2.
