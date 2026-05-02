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

dyn_deg_sensor(S,Z) :- zone2sensor(Z,S), assigned_zone_unit(Z,U).
dyn_unit_zone_sensor(U,SN) :- assigned_zone_unit(Z,U), zone2sensor(Z,SN).
dyn_sat_unit_zone_sensor(U,SN) :- assigned_zone_unit(Z,U), zone2sensor(Z,SN), assigned_sensor(SN).
dyn_zone_sensor_degree(Z,D) :- zone2sensor(Z,SN), degree_sensor(SN,D).
dyn_direct_con_sensor(Z,U,S) :- assigned_sensor_unit(S,U), zone2sensor(Z,S).
dyn_sensor_degree(S,D) :- degree_sensor(S,D).
dyn_zone_degree(Z,D) :- degree_zone(Z,D).


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


% Originale: #heuristic assigned_sensor_unit(S,U) : assignable_sensor_unit(S,U), not not_assigned_sensor_unit(S,U),  NAZ = #count{Z: assigned_zone_unit(Z,_)},  NAS = #count{SN: assigned_sensor_unit(SN,_)},  maxSensor(MaxS), NAS < MaxS, NAZ > NAS,  Deg_sensor_dyn = #count{Z: dyn_deg_sensor(S,Z)},  Forbidden_placement_total = #max{N: num_forbidden_places_of_sensors(S,N)},   Num_constr_on_sensor_places_by_zones_on_U1     = 	#count {SN: dyn_unit_zone_sensor(U1,SN)}, Num_constr_on_sensor_places_by_zones_on_U	 = 	#count {SN: dyn_unit_zone_sensor(U,SN)}, Num_constr_on_sensor_places_by_zones_on_U2	 =	#count {SN: dyn_unit_zone_sensor(U2,SN)}, Num_sat_constr_on_sensor_places_by_zones_on_U1  = 	#count {SN: dyn_sat_unit_zone_sensor(U1,SN)}, Num_sat_constr_on_sensor_places_by_zones_on_U	 = 	#count {SN: dyn_sat_unit_zone_sensor(U,SN)}, Num_sat_constr_on_sensor_places_by_zones_on_U2	 =	#count {SN: dyn_sat_unit_zone_sensor(U2,SN)}, comUnit(U),  Deg_sensor_stat = #max{D: dyn_sensor_degree(S,D)}. [Deg_sensor_dyn * 1000 + Forbidden_placement_total * 100 + (Num_constr_on_sensor_places_by_zones_on_U1 + Num_constr_on_sensor_places_by_zones_on_U + Num_constr_on_sensor_places_by_zones_on_U2 - Num_sat_constr_on_sensor_places_by_zones_on_U1 - Num_sat_constr_on_sensor_places_by_zones_on_U - Num_sat_constr_on_sensor_places_by_zones_on_U2) * 10 + (6 - Deg_sensor_stat)@0, true]
% WARNING: body positivi non sulla tupla target ignorati nel lazy diretto: maxSensor, comUnit.
__heuristic(__target(assigned_sensor_unit), assignable_sensor_unit, __n_not_assigned_sensor_unit, __bind(naz, __count(assigned_zone_unit, 0)), __bind(nas, __count(assigned_sensor_unit, 0)), __bind(deg_sensor_dyn, __count(dyn_deg_sensor, 1, __filter(0, 0))), __bind(forbidden_placement_total, __max(num_forbidden_places_of_sensors, 1, __filter(0, 0))), __bind(num_constr_on_sensor_places_by_zones_on_u1, __count(dyn_unit_zone_sensor, 1)), __bind(num_constr_on_sensor_places_by_zones_on_u, __count(dyn_unit_zone_sensor, 1, __filter(0, 1))), __bind(num_constr_on_sensor_places_by_zones_on_u2, __count(dyn_unit_zone_sensor, 1)), __bind(num_sat_constr_on_sensor_places_by_zones_on_u1, __count(dyn_sat_unit_zone_sensor, 1)), __bind(num_sat_constr_on_sensor_places_by_zones_on_u, __count(dyn_sat_unit_zone_sensor, 1, __filter(0, 1))), __bind(num_sat_constr_on_sensor_places_by_zones_on_u2, __count(dyn_sat_unit_zone_sensor, 1)), __bind(deg_sensor_stat, __max(dyn_sensor_degree, 1, __filter(0, 0))), __weight(__add(__add(__add(__mul(deg_sensor_dyn, 1000), __mul(forbidden_placement_total, 100)), __mul(__sub(__sub(__sub(__add(__add(num_constr_on_sensor_places_by_zones_on_u1, num_constr_on_sensor_places_by_zones_on_u), num_constr_on_sensor_places_by_zones_on_u2), num_sat_constr_on_sensor_places_by_zones_on_u1), num_sat_constr_on_sensor_places_by_zones_on_u), num_sat_constr_on_sensor_places_by_zones_on_u2), 10)), __sub(6, deg_sensor_stat))), __priority(0), true).

% Originale: #heuristic assigned_sensor_unit(S, U) : assignable_sensor_unit(S,U), not not_assigned_sensor_unit(S,U),  comUnit(U),  NAZ = #count{Z: assigned_zone_unit(Z,_)},  NAS = #count{SN: assigned_sensor_unit(SN,_)},  NAZ = 2, NAS = 1,  Assigned_sensors_on_unit = #count{SN: assigned_sensor_unit(SN,U)}. [2 - Assigned_sensors_on_unit@2, true]
% WARNING: body positivi non sulla tupla target ignorati nel lazy diretto: comUnit.
__heuristic(__target(assigned_sensor_unit), assignable_sensor_unit, __n_not_assigned_sensor_unit, __bind(naz, __count(assigned_zone_unit, 0)), __bind(nas, __count(assigned_sensor_unit, 0)), __bind(assigned_sensors_on_unit, __count(assigned_sensor_unit, 0, __filter(1, 1))), __weight(__sub(2, assigned_sensors_on_unit)), __priority(2), true).

% Originale: #heuristic assigned_zone_unit(Z, U) : assignable_zone_unit(Z,U), not not_assigned_zone_unit(Z,U),  comUnit(U),  Assigned_zones_unit = #count{ZN: assigned_zone_unit(ZN,U)}, Deg_zone_stat = #max{D: dyn_zone_degree(Z,D)}. [Assigned_zones_unit * 10 + (6 - Deg_zone_stat)@1, true]
% WARNING: body positivi non sulla tupla target ignorati nel lazy diretto: comUnit.
__heuristic(__target(assigned_zone_unit), assignable_zone_unit, __n_not_assigned_zone_unit, __bind(assigned_zones_unit, __count(assigned_zone_unit, 0, __filter(1, 1))), __bind(deg_zone_stat, __max(dyn_zone_degree, 1, __filter(0, 0))), __weight(__add(__mul(assigned_zones_unit, 10), __sub(6, deg_zone_stat))), __priority(1), true).


% Originale: #heuristic assigned_zone_unit(Z, U) : assignable_zone_unit(Z,U), not not_assigned_zone_unit(Z,U),  comUnit(U),  NAZ = #count {ZN: assigned_zone_unit(ZN,_)},  NAS = #count {S: assigned_sensor_unit(S,_)},  NAZ = 2, NAS = 2,  Min_constraint_degree = #min{D: dyn_zone_sensor_degree(Z,D)},  Direct_con_sensors = #count{S: dyn_direct_con_sensor(Z,U,S)}. [(6 - Min_constraint_degree) * 10 + Direct_con_sensors@2, true]
% WARNING: body positivi non sulla tupla target ignorati nel lazy diretto: comUnit.
__heuristic(__target(assigned_zone_unit), assignable_zone_unit, __n_not_assigned_zone_unit, __bind(naz, __count(assigned_zone_unit, 0)), __bind(nas, __count(assigned_sensor_unit, 0)), __bind(min_constraint_degree, __min(dyn_zone_sensor_degree, 1, __filter(0, 0))), __bind(direct_con_sensors, __count(dyn_direct_con_sensor, 2, __filter(0, 0), __filter(1, 1))), __weight(__add(__mul(__sub(6, min_constraint_degree), 10), direct_con_sensors)), __priority(2), true).
	


