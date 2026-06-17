% ============================================================
% PUP (Partner Units Problem) - GROUND ALPHA (ga).
% Architettura: ALPHA/Evaluation/PUP/encoding-alpha-prologheu-double.asp
%
% Come PUP_gc.lp, ma le condizioni di attivazione delle euristiche
% simulano la semantica di Alpha sullo stato parziale, replicando il
% pattern di BSP_ga.lp (sum_value + bound) sugli aggregati:
%
%   - ogni variabile-aggregato e' unrollata su un DOMINIO STATICO
%     (deg_value, forb_value, unit_count_value, occ_value) e legata
%     all'aggregato da un BOUND invece che da un assegnamento esatto;
%   - per le componenti con peso CRESCENTE si usa  V <= #agg{...}:
%     la condizione diventa vera in modo monotono appena lo stato
%     parziale raggiunge il bound (attivazione "anticipata", come la
%     valutazione lazy di Alpha) e la selezione max-W di clasp
%     ricostruisce il valore corrente esatto;
%   - per N0,N1,N2 (peso DEcrescente: spazi disponibili) si usa
%     V >= #max{...}: la selezione max-W sceglie il minimo V provato,
%     cioe' di nuovo il valore corrente. Un lower bound qui renderebbe
%     la componente inerte (max-W sceglierebbe sempre Ni=0);
%   - come BSP_ga.lp elimina "not c(X)", qui sono eliminate le
%     condizioni NAF "not not_assigned_..." (in Alpha sarebbero vere
%     anche su atomi indefiniti; clasp comunque non decide mai atomi
%     gia' assegnati).
%
% Stessi adattamenti di dominio di PUP_gc.lp (bound comUnit sugli
% assignable, capacita' come aggregato, regola distanza-2 rimossa), piu': !=, sensorNumbers(0..2),
% #max{0; ...} (max di insieme vuoto = 0), offset +100000 sul peso
% delle zone per appiattire il ranking globale [W@1] > [W@0].
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

%%% domini statici dei valori per l'unrolling (pattern sum_value di BSP_ga)

degree_sensor(S,N) :- zone2sensor(Z,S), N = #count{ZN: zone2sensor(ZN,S)}.
max_sensor_degree(M) :- M = #max{N: degree_sensor(_,N)}.

deg_value(0..M) :- max_sensor_degree(M).   % grado dinamico di un sensore
forb_value(0..6).                          % posizioni proibite (cap 2+2+2)
unit_count_value(0..2).                    % elementi assegnati a una unit
occ_value(0..2).                           % occupazione sensori di una unit

%%% constraints

:- zone2sensor(Z,_), not assigned_zone(Z).
:- zone2sensor(_,S), not assigned_sensor(S).

:- zone2sensor(Z,S), assigned_sensor_unit(S,U1), assigned_zone_unit(Z,U2), |U1-U2| > 1.


%%% heuristics (semantica alpha simulata: domini statici + bound)

#heuristic assigned_sensor_unit(S,U) :
        assignable_sensor_unit(S,U),

        degree_sensor(S,DS),
        deg_value(Deg_sensor_dyn), Deg_sensor_dyn <= DS,
        Deg_sensor_dyn <= #count{Z: zone2sensor(Z,S), assigned_zone_unit(Z,_)},

        forb_value(Forbidden_placement_total),
        Forbidden_placement_total <= #max{0; N: num_forbidden_places_of_sensors(S,N)},

        unit_count_value(Assigned_sensors_unit),
        Assigned_sensors_unit <= #count{SN: assigned_sensor_unit(SN,U)},

        unit_count_value(Direct_con_zones),
        Direct_con_zones <= #count{Z1: assigned_zone_unit(Z1,U), zone2sensor(Z1,S)},

        W = Deg_sensor_dyn * 10000 + Forbidden_placement_total * 1000
            + Assigned_sensors_unit * 100 + Direct_con_zones * 10.  [W@0, true]


#heuristic assigned_zone_unit(Z,U) :
        assignable_zone_unit(Z,U),

        unit_count_value(Assigned_zones_unit),
        Assigned_zones_unit <= #count{ZN: assigned_zone_unit(ZN,U)},

        U1 = U - 1,
        U2 = U + 1,

        occ_value(N0), N0 >= #max{0; N: num_sensors_on_unit(N,U)},

        occ_value(N1), N1 >= #max{0; NA: num_sensors_on_unit(NA,U1)},
        occ_value(N2), N2 >= #max{0; NB: num_sensors_on_unit(NB,U2)},

        Available_spaces_for_sensors = 6 - (N0 + N1 + N2),

        W = Assigned_zones_unit * 10 + Available_spaces_for_sensors + 100000.  [W@1, true]

#show assigned_zone_unit/2.
#show assigned_sensor_unit/2.
