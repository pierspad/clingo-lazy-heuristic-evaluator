%%% initial assignment

assigned_zone_unit(1,1).


maxZone(N) :- N = #count{Z: zone2sensor(Z,S)}.
maxSensor(N) :- N = #count{S: zone2sensor(Z,S)}.


sensorNumbers(0..N) :- maxSensor(N).
zoneNumbers(0..N) :- maxZone(N).

degree_sensor(S,N) :- zone2sensor(Z,S), N = #count{ZN:zone2sensor(ZN,S)}.
degree_zone(Z,N) :- zone2sensor(Z,S), N = #count{SN:zone2sensor(Z,SN)}.


%%% assign zones

assignable_zone_unit(Z,U) :-  zone2sensor(Z,S),  assigned_sensor_unit(S,U).
assignable_zone_unit(Z,U-1) :-  zone2sensor(Z,S),  assigned_sensor_unit(S,U).
assignable_zone_unit(Z,U+1) :-  zone2sensor(Z,S),  assigned_sensor_unit(S,U).

zone_blocked_on_unit(Z,UZ) :- assigned_sensor_unit(S,US),  zone2sensor(Z,S), comUnit(UZ), (US-UZ)**2 > 1.

zone_blocked_on_unit(Z,UZ) :- assigned_zone_unit(Z1,UZ1), zone2sensor(Z,S), zone2sensor(Z1,S), comUnit(UZ), (UZ-UZ1)**2 > 4.

zone_blocked_on_unit(Z,UZ) :- assigned_zone_unit(Z1,UZ1), zone2sensor(Z,S), zone2sensor(Z1,S), comUnit(UZ), (UZ-UZ1)**2 = 4, comUnit(UZ2), (UZ1-UZ2)**2 = 1, (UZ-UZ2)**2 = 1, assigned_sensor_unit(S1,UZ2), assigned_sensor_unit(S2,UZ2), S <> S1, S1 <> S2, S2 <> S.

zone_blocked_on_unit(Z,U) :- assigned_zone_unit(Z1,U), assigned_zone_unit(Z2,U), Z1 <> Z2, zone2sensor(Z,_), Z <> Z1, Z <> Z2.
zone_blocked_on_unit(Z,U) :- assigned_zone_unit(Z,U1), comUnit(U), U1 <> U.

%%% zone choice

assigned_zone_unit(Z,U)     :- assignable_zone_unit(Z,U), not not_assigned_zone_unit(Z,U), 0 < U.
not_assigned_zone_unit(Z,U) :- assignable_zone_unit(Z,U), not assigned_zone_unit(Z,U), 0 < U.
not_assigned_zone_unit(Z,U) :- zone_blocked_on_unit(Z,U).


%%% assign sensors

assignable_sensor_unit(S,U) :-  zone2sensor(Z,S),  assigned_zone_unit(Z,U).
assignable_sensor_unit(S,U-1) :-  zone2sensor(Z,S),  assigned_zone_unit(Z,U).
assignable_sensor_unit(S,U+1) :-  zone2sensor(Z,S),  assigned_zone_unit(Z,U).

sensor_blocked_on_unit(S,US) :- assigned_zone_unit(Z,UZ), zone2sensor(Z,S), comUnit(US), (UZ-US)**2 > 1.

sensor_blocked_on_unit(S,US) :- assigned_sensor_unit(S1, US1), zone2sensor(Z,S), zone2sensor(Z, S1), comUnit(US), (US-US1)**2 > 4.

sensor_blocked_on_unit(S,US) :- assigned_sensor_unit(S1,US1), zone2sensor(Z,S), zone2sensor(Z, S1), comUnit(US), (US-US1)**2 = 4, comUnit(US2), (US1-US2)**2 = 1, (US-US2)**2 = 1, assigned_zone_unit(Z1, US2), assigned_zone_unit(Z2, US2), Z <> Z1, Z1 <> Z2, Z2 <> Z.

sensor_blocked_on_unit(S,U) :- assigned_sensor_unit(S1,U), assigned_sensor_unit(S2,U), S1 <> S2, zone2sensor(_, S), S <> S1, S <> S2.
sensor_blocked_on_unit(S,U) :- assigned_sensor_unit(S, U1), comUnit(U), U1 <> U.

%%% sensor choice

assigned_sensor_unit(S,U)     :- assignable_sensor_unit(S,U), not not_assigned_sensor_unit(S,U), 0 < U.
not_assigned_sensor_unit(S,U) :- assignable_sensor_unit(S,U), not assigned_sensor_unit(S,U), 0 < U.
not_assigned_sensor_unit(S,U) :- sensor_blocked_on_unit(S,U).


assigned_zone(Z) :- assigned_zone_unit(Z,U).
assigned_sensor(S) :- assigned_sensor_unit(S,U).


%%% auxiliary predicates for heuristics


num_sensors_on_unit(N,U) :-  comUnit(U), sensorNumbers(N), N <= #count{S1: assigned_sensor_unit(S1,U)}.
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

:- zone2sensor(Z,S), assigned_sensor_unit(S,U1), assigned_zone_unit(Z,U2), (U1-U2)**2 > 1.


%%% heuristics


#heuristic assigned_sensor_unit(S,U) :
    assignable_sensor_unit(S,U),
    not not_assigned_sensor_unit(S,U),

    NAZ = #count{Z: assigned_zone_unit(Z,_)},

    NAS = #count{SN: assigned_sensor_unit(SN,_)},

    maxSensor(MaxS),
    NAS < MaxS,
    NAZ > NAS,

    Deg_sensor_dyn = #count{Z: zone2sensor(Z,S), assigned_zone_unit(Z,_)},

    Forbidden_placement_total = #max{N: num_forbidden_places_of_sensors(S,N)},


    Num_constr_on_sensor_places_by_zones_on_U1     = 	#count {SN: assigned_zone_unit(Z,U1), zone2sensor(Z,SN)},
    Num_constr_on_sensor_places_by_zones_on_U	 = 	#count {SN: assigned_zone_unit(Z,U),   zone2sensor(Z,SN)},
    Num_constr_on_sensor_places_by_zones_on_U2	 =	#count {SN: assigned_zone_unit(Z,U2), zone2sensor(Z,SN)},
    Num_sat_constr_on_sensor_places_by_zones_on_U1  = 	#count {SN: assigned_zone_unit(Z,U1), zone2sensor(Z,SN),  assigned_sensor(SN)},
    Num_sat_constr_on_sensor_places_by_zones_on_U	 = 	#count {SN: assigned_zone_unit(Z,U),   zone2sensor(Z,SN),  assigned_sensor(SN)},
    Num_sat_constr_on_sensor_places_by_zones_on_U2	 =	#count {SN: assigned_zone_unit(Z,U2), zone2sensor(Z,SN),  assigned_sensor(SN)},


    Open_constraints_on_placement = Num_constr_on_sensor_places_by_zones_on_U1
                                    + Num_constr_on_sensor_places_by_zones_on_U
                                    + Num_constr_on_sensor_places_by_zones_on_U2
                                    - Num_sat_constr_on_sensor_places_by_zones_on_U1
                                    - Num_sat_constr_on_sensor_places_by_zones_on_U
                                    - Num_sat_constr_on_sensor_places_by_zones_on_U2,
    comUnit(U),
    degree_sensor(S,Deg_sensor_stat),
    Minus_deg_sensor_stat = 6 - Deg_sensor_stat,


    W = Deg_sensor_dyn * 1000 + Forbidden_placement_total * 100 + Open_constraints_on_placement * 10 + Minus_deg_sensor_stat.  [W@0]

#heuristic assigned_sensor_unit(S, U) :
    assignable_sensor_unit(S,U),
    not not_assigned_sensor_unit(S,U),

    comUnit(U),

    NAZ = #count{Z: assigned_zone_unit(Z,_)},

    NAS = #count{SN: assigned_sensor_unit(SN,_)},

    NAZ = 2,
    NAS = 1,

    Assigned_sensors_on_unit = #count{SN: assigned_sensor_unit(SN,U)},
    Open_positions_on_unit = 2 - Assigned_sensors_on_unit. [Open_positions_on_unit@2]

#heuristic assigned_zone_unit(Z, U) :
    assignable_zone_unit(Z,U),
    not not_assigned_zone_unit(Z,U),

    comUnit(U),

    Assigned_zones_unit = #count{ZN: assigned_zone_unit(ZN,U)},
    degree_zone(Z, Deg_zone_stat),
    Minus_deg_zone_stat = 6 - Deg_zone_stat,
    W = Assigned_zones_unit * 10 + Minus_deg_zone_stat. [W@1]


#heuristic assigned_zone_unit(Z, U) :
    assignable_zone_unit(Z,U),
    not not_assigned_zone_unit(Z,U),

    comUnit(U),

    NAZ = #count {ZN: assigned_zone_unit(ZN,_)},

    NAS = #count {S: assigned_sensor_unit(S,_)},

    NAZ = 2,
    NAS = 2,

    Min_constraint_degree = #min{D: zone2sensor(Z,SN), degree_sensor(SN,D)},

    Minus_min_constraint_degree = 6 - Min_constraint_degree,

    Direct_con_sensors = #count{S: assigned_sensor_unit(S,U), zone2sensor(Z,S)},

    W = Minus_min_constraint_degree * 10 + Direct_con_sensors. [W@2]
	


