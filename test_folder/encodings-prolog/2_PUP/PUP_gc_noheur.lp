% ============================================================
% PUP (Partner Units Problem) - baseline SENZA euristiche.
% Architettura: ALPHA/Evaluation/PUP/encoding-alpha-prologheu-double.asp
%
% Contiene solo la logica di dominio: fatti iniziali, propagazione
% induttiva della scelta (doppia negazione su assigned_zone_unit /
% assigned_sensor_unit) e vincoli di integrita'.
% Nessuna direttiva #heuristic e nessun predicato ausiliario
% (num_sensors_on_unit/2, num_forbidden_places_of_sensors/2, ...).
%
% Adattamenti rispetto al file Alpha originale:
%   - operatore di disuguaglianza: !=  (Alpha usa <>)
%   - bound comUnit(U+-1) sulle regole assignable_*: senza, la catena
%     induttiva U+1 e' illimitata a destra e il grounding di gringo
%     DIVERGE (Alpha la esplora lazy, gringo materializza tutto);
%   - vincoli di capacita' riscritti come aggregato monotono
%     2 <= #count{...} (equivalente alla coppia esistenziale, ma con
%     grounding lineare invece che cubico);
%   - rimossa (da TUTTE le varianti, uniformemente) la regola di blocco
%     "zone/sensori a distanza 2 con unit di mezzo piena": e' solo
%     propagazione ridondante (il vincolo di adiacenza la sussume) e
%     il suo grounding e' cubico.
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
    comUnit(UZ), (US-UZ)**2 > 1.

zone_blocked_on_unit(Z,UZ) :- assigned_zone_unit(Z1,UZ1), zone2sensor(Z,S),
    zone2sensor(Z1,S), comUnit(UZ), (UZ-UZ1)**2 > 4.

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
    comUnit(US), (UZ-US)**2 > 1.

sensor_blocked_on_unit(S,US) :- assigned_sensor_unit(S1,US1), zone2sensor(Z,S),
    zone2sensor(Z,S1), comUnit(US), (US-US1)**2 > 4.

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

:- zone2sensor(Z,S), assigned_sensor_unit(S,U1), assigned_zone_unit(Z,U2), (U1-U2)**2 > 1.

#show assigned_zone_unit/2.
#show assigned_sensor_unit/2.
