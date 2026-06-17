% ============================================================
% PUP (Partner Units Problem) - GROUND CLINGO (gc).
% Architettura: ALPHA/Evaluation/PUP/encoding-alpha-prologheu-double.asp
%
% Direttive #heuristic native di clingo con AGGREGATI DINAMICI di
% ASSEGNAMENTO (V = #count{...}, V = #max{...}) legati allo stato
% parziale del solver. Per groundarle, gringo e' costretto a
% "unrollare" ogni variabile-aggregato su tutti i valori possibili:
% ogni direttiva esplode nel prodotto cartesiano
%   Deg x Forbidden x Assigned x Direct   (sensori)
%   Assigned x N0 x N1 x N2               (zone)
% per ciascuna coppia ground (S,U) / (Z,U). Questa e' l'esplosione
% combinatoria misurata dal benchmark.
%
% Adattamenti rispetto al file Alpha originale (motivati nei commenti):
%   - !=  al posto di  <>
%   - sensorNumbers(0..2) al posto di sensorNumbers(0..maxSensor):
%     la capacita' di una unit e' 2, quindi i contatori oltre 2 non
%     sono mai rilevanti; senza questo cap il solo predicato ausiliario
%     num_forbidden_places_of_sensors esploderebbe in TUTTE le varianti
%     (anche lazy e baseline), falsando il confronto.
%   - #max{0; ...} include l'elemento costante 0: replica la convenzione
%     "max di insieme vuoto = 0" usata da Alpha e dal runtime Prolog
%     (dyn_max) ed evita il valore #inf di clingo.
%   - clamp "<= 2" sui #count per-unit: limite di capacita'; senza
%     clamp gringo enumererebbe valori fino al numero di elementi
%     possibili sull'unit (~O(n)) invece che fino alla capacita'.
%   - il peso delle zone ha offset +100000: in clasp la @priority
%     arbitra solo modifiche sullo stesso atomo, NON il ranking
%     globale tra atomi (cfr. commento in encoding-hclingo.asp);
%     l'ordine globale zone-prima-dei-sensori di [W@1] vs [W@0]
%     va quindi appiattito nel level. @0/@1 sono mantenute per
%     tracciabilita' verso l'encoding originale.
%
% Le istanze forniscono: comUnit/1, zone2sensor/2.
% ============================================================

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

% capacita' di una unit: al massimo 2 sensori (vedi header).
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


%%% heuristics (semantica clingo: aggregati di assegnamento esatti,
%%% condizione negativa NAF nativa "not not_assigned_...")

#heuristic assigned_sensor_unit(S,U) :
        assignable_sensor_unit(S,U),
        not not_assigned_sensor_unit(S,U),

        Deg_sensor_dyn = #count{Z: zone2sensor(Z,S), assigned_zone_unit(Z,_)},

        Forbidden_placement_total = #max{0; N: num_forbidden_places_of_sensors(S,N)},

        Assigned_sensors_unit = #count{SN: assigned_sensor_unit(SN,U)},
        Assigned_sensors_unit <= 2,

        Direct_con_zones = #count{Z1: assigned_zone_unit(Z1,U), zone2sensor(Z1,S)},
        Direct_con_zones <= 2,

        W = Deg_sensor_dyn * 10000 + Forbidden_placement_total * 1000
            + Assigned_sensors_unit * 100 + Direct_con_zones * 10.  [W@0, true]


#heuristic assigned_zone_unit(Z,U) :
        assignable_zone_unit(Z,U),
        not not_assigned_zone_unit(Z,U),

        Assigned_zones_unit = #count{ZN: assigned_zone_unit(ZN,U)},
        Assigned_zones_unit <= 2,

        U1 = U - 1,
        U2 = U + 1,

        N0 = #max{0; N: num_sensors_on_unit(N,U)},

        N1 = #max{0; NA: num_sensors_on_unit(NA,U1)},
        N2 = #max{0; NB: num_sensors_on_unit(NB,U2)},

        Available_spaces_for_sensors = 6 - (N0 + N1 + N2),

        W = Assigned_zones_unit * 10 + Available_spaces_for_sensors + 100000.  [W@1, true]

#show assigned_zone_unit/2.
#show assigned_sensor_unit/2.
