% ============================================================
% PUP (Partner Units Problem) - LAZY, backend NATIVE, semantica CLINGO (lc).
% Equivalente nativo di encodings-prolog/2_PUP/PUP_lc.lp.
%
% Logica di dominio IDENTICA al file Prolog. Le euristiche NON sono
% stringhe Prolog ma fatti __heuristic(...) letti dal propagatore C++.
%
% NOTA SUI JOIN: il DSL nativo aggrega su UN solo predicato sorgente
% (filtrato verso gli argomenti del target), quindi i join Prolog
%   aggregate_all(count, (holds(p(..)), holds(q(..))), N)
% sono precompilati come predicati ausiliari e poi contati con __count:
%   sensor_assigned_zone(S,Z)  := zone S serve la zona Z, e Z e' assegnata
%   sensor_zone_on_unit(S,U,Z) := zona Z su unit U che serve il sensore S
% Questi ausiliari sono derivati (nessun vincolo su di essi): non cambiano
% gli answer set, servono solo come sorgente d'aggregato incrementale.
%
% Mappa aggregati -> DSL nativo (semantica clingo):
%   Deg    = #zone assegnate servite da S      -> __count(sensor_assigned_zone, filter S)
%   Forb   = max num_forbidden_places_of_sensors(S,N)  -> __max(.., idx N, filter S)
%   Cnt    = #sensori su unit U                 -> __count(assigned_sensor_unit, filter U)
%   Direct = #zone su U che servono S           -> __count(sensor_zone_on_unit, filter S,U)
%   A      = #zone su unit U                     -> __count(assigned_zone_unit, filter U)
%   M0/M1/M2 = max num_sensors_on_unit su U/U-1/U+1 -> __max(.., idx N, filter U[+off])
% alpha_not(p) -> __n_p (+ __semantics(clingo)). Esegui con: --heuristic=Domain
% ============================================================

% ============================================================
% PUP (Partner Units Problem) - LAZY ALPHA (la, backend Prolog).
% Architettura: ALPHA/Evaluation/PUP/encoding-alpha-prologheu-double.asp
%
% Logica di dominio e predicati ausiliari IDENTICI a PUP_gc.lp, ma
% nessuna direttiva #heuristic nativa: le euristiche sono iniettate
% come stringhe Prolog tramite heuristic("...") e valutate a runtime
% dal propagatore (LAZY_HEURISTIC_BACKEND=prolog). Il grounder non
% vede alcun aggregato euristico: niente esplosione combinatoria.
%
% Traduzione degli aggregati (runtime SWI-Prolog):
%   #count{...}  -> aggregate_all(count, (holds(...), ...), V)
%   #max{0; ...} -> dyn_max(holds(...), N, V)   (0 se l'insieme e' vuoto)
% Condizioni negative con semantica CLINGO:
%   not p(X)     -> alpha_not(p(X))   (vera solo se p(X) e' assegnato falso)
% Sicurezza a runtime: target_available(...) garantisce che il target
% sia ancora libero (ne' vero ne' falso).
%
% Ranking globale del backend: (Priority, Weight) decrescenti; la
% priorita' 1 delle zone replica nativamente [W@1] > [W@0] del file
% originale (in gc/ga e' appiattita nel peso con offset +100000).
%
% Stessi adattamenti di dominio di PUP_gc.lp: !=, sensorNumbers(0..2).
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

:- zone2sensor(Z,S), assigned_sensor_unit(S,U1), assigned_zone_unit(Z,U2), (U1-U2)**2 > 1.



%%% ausiliari per i join degli aggregati nativi (derivati, non mostrati)

sensor_assigned_zone(S,Z)  :- zone2sensor(Z,S), assigned_zone_unit(Z,_).
sensor_zone_on_unit(S,U,Z) :- zone2sensor(Z,S), assigned_zone_unit(Z,U).

%%% heuristics (DSL nativo, semantica alpha)

% --- sensori (priorita' 0) ---
% W = Deg*10000 + Forb*1000 + Cnt*100 + Direct*10
__heuristic(__target(assigned_sensor_unit),
            assignable_sensor_unit,
            __n_not_assigned_sensor_unit,
            __bind(deg,    __count(sensor_assigned_zone, 0, __filter(0,0))),
            __bind(forb,   __max(num_forbidden_places_of_sensors, 1, __filter(0,0))),
            __bind(cnt,    __count(assigned_sensor_unit, 1, __filter(1,1))),
            __bind(direct, __count(sensor_zone_on_unit, 0, __filter(0,0), __filter(1,1))),
            __weight(__add(__add(__add(__mul(deg,10000), __mul(forb,1000)),
                                 __mul(cnt,100)), __mul(direct,10))),
            __priority(0), __semantics(clingo), __modifier(true)).

% --- zone (priorita' 1) ---
% W = A*10 + (6 - (M0 + M1 + M2))
__heuristic(__target(assigned_zone_unit),
            assignable_zone_unit,
            __n_not_assigned_zone_unit,
            __bind(a,  __count(assigned_zone_unit, 1, __filter(1,1))),
            __bind(m0, __max(num_sensors_on_unit, 0, __filter(1,1))),
            __bind(m1, __max(num_sensors_on_unit, 0, __filter(1,1,-1))),
            __bind(m2, __max(num_sensors_on_unit, 0, __filter(1,1,1))),
            __weight(__sub(__sub(__sub(__add(__mul(a,10), 6), m0), m1), m2)),
            __priority(1), __semantics(clingo), __modifier(true)).

#show assigned_zone_unit/2.
#show assigned_sensor_unit/2.
