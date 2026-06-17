% ============================================================
% HRP - LAZY CLINGO (lc), backend NATIVE (propagatore C++, fatti __heuristic).
% Identico a HRP_la.lp ma __semantics(clingo): un __n_<pred> richiede che il
% predicato sia FALSO (non basta indeciso). I 'not' su stato parziale
% scattano piu' tardi -> guida tipicamente piu' debole della 'la' (confronto
% alpha vs clingo sulla negazione; HRP non ha aggregati).
% Esegui con: --heuristic=Domain.
% ============================================================

% --- domini di cabinet e stanze ---
cabinetDomain(C) :- cabinetDomainNew(C).
roomDomain(R)    :- roomDomainNew(R).
cabinetDomain(C) :- legacyCabinet(C).   % i cabinet legacy entrano nel dominio
roomDomain(R)    :- legacyRoom(R).

% --- guess di quali cabinet/stanze sono usati ---
{ cabinet(C) } :- cabinetDomain(C).
{ room(R) }    :- roomDomain(R).

% simmetria: usa prima i cabinet/stanze con id minore
room(R1)    :- roomDomainNew(R1), roomDomainNew(R2), room(R2), R1 < R2.
cabinet(C1) :- cabinetDomainNew(C1), cabinetDomainNew(C2), cabinet(C2), C1 < C2.

% --- assegnamento cosa -> cabinet ---
{ cabinetTOthing(C,T) } :- cabinetDomain(C), thing(T).
thingHasCabinet(T) :- cabinetTOthing(C,T).
:- thing(T), not thingHasCabinet(T).                                   % (1) ogni cosa in un cabinet
:- thing(T), cabinetTOthing(C1,T), cabinetTOthing(C2,T), C1 < C2.      % al piu' un cabinet per cosa
:- 6 <= #count { T : cabinetTOthing(C,T), thing(T) }, cabinet(C).      % (2) max 5 cose per cabinet

% --- assegnamento cabinet -> stanza ---
{ roomTOcabinet(R,C) } :- roomDomain(R), cabinet(C).
cabinetHasRoom(C) :- roomTOcabinet(R,C).
:- cabinet(C), not cabinetHasRoom(C).                                  % (3) ogni cabinet in una stanza
:- cabinet(C), roomTOcabinet(R1,C), roomTOcabinet(R2,C), R1 < R2.      % al piu' una stanza per cabinet
:- 5 <= #count { C : roomTOcabinet(R,C), cabinetDomain(C) }, room(R).  % (4) max 4 cabinet per stanza

% --- una stanza appartiene alla persona che vi ripone le sue cose ---
personTOroom(P,R) :- personTOthing(P,T), cabinetTOthing(C,T), roomTOcabinet(R,C).
legacyPersonRoom(P,R) :- personTOthing(P,T), legacyCabinetThing(C,T), legacyRoomCabinet(R,C).

% (5) cose di persone diverse non possono stare nello stesso cabinet
:- cabinetTOthing(C,T1), cabinetTOthing(C,T2), personTOthing(P1,T1), personTOthing(P2,T2), P1 < P2.
% una stanza non puo' appartenere a 2 persone diverse
:- personTOroom(P1,R), personTOroom(P2,R), P1 < P2.

room(R)    :- roomTOcabinet(R,C).
room(R)    :- personTOroom(P,R).
cabinet(C) :- cabinetTOthing(C,T).
cabinet(C) :- roomTOcabinet(R,C).

% --- MODIFIED PROBLEM: cose corte/lunghe, cabinet piccoli/alti ---
thingShort(T) :- thing(T), not thingLong(T).
:- thingLong(T), thingShort(T).

cabinetHigh(C)  :- cabinet(C), not cabinetSmall(C).
cabinetSmall(C) :- cabinet(C), not cabinetHigh(C).
:- cabinet(C), cabinetHigh(C), cabinetSmall(C).
cabinetHigh(C) :- thingLong(T), cabinetTOthing(C,T).      % (HRP-2) cosa lunga -> cabinet alto

% (HRP-3) slot per stanza: cabinet piccolo = 1, alto = 2, max 4
cabinetSize(C,1) :- cabinet(C), cabinetSmall(C).
cabinetSize(C,2) :- cabinet(C), cabinetHigh(C).
roomTOcabinetSize(R,C,S) :- roomTOcabinet(R,C), cabinetSize(C,S).
:- 5 <= #sum { S,C : roomTOcabinetSize(R,C,S), cabinetDomain(C) }, room(R).

% --- TRANSFORMATION RULES: riuso/cancellazione del legacy ---
reuseCabinetThing(C,T)  :- legacyCabinetThing(C,T), not deleteCabinetThing(C,T).
deleteCabinetThing(C,T) :- legacyCabinetThing(C,T), not reuseCabinetThing(C,T).
reuseRoomCabinet(R,C)  :- legacyRoomCabinet(R,C), not deleteRoomCabinet(R,C).
deleteRoomCabinet(R,C) :- legacyRoomCabinet(R,C), not reuseRoomCabinet(R,C).
reusePersonRoom(P,R)  :- legacyPersonRoom(P,R), not deletePersonRoom(P,R).
deletePersonRoom(P,R) :- legacyPersonRoom(P,R), not reusePersonRoom(P,R).
reuseCabinet(C)  :- legacyCabinet(C), not deleteCabinet(C).
deleteCabinet(C) :- legacyCabinet(C), not reuseCabinet(C).
reuseRoom(R)  :- legacyRoom(R), not deleteRoom(R).
deleteRoom(R) :- legacyRoom(R), not reuseRoom(R).

% riuso => l'atomo fa parte della configurazione
cabinetTOthing(C,T) :- reuseCabinetThing(C,T).
roomTOcabinet(R,C)  :- reuseRoomCabinet(R,C).
personTOroom(P,R)   :- reusePersonRoom(P,R).
cabinet(C) :- reuseCabinet(C).
room(R)    :- reuseRoom(R).

% cancellazione => l'atomo non puo' essere usato
:- cabinetTOthing(C,T), deleteCabinetThing(C,T).
:- roomTOcabinet(R,C),  deleteRoomCabinet(R,C).
:- personTOroom(P,R),   deletePersonRoom(P,R).
:- cabinet(C), deleteCabinet(C).
:- room(R),    deleteRoom(R).

#show cabinetTOthing/2.
#show roomTOcabinet/2.

% ===== predicati ausiliari per le euristiche =====
maxCabinet(C) :- cabinetDomainNew(C), not cabinetDomainNew(C+1).
maxRoom(R)    :- roomDomainNew(R), not roomDomainNew(R+1).
fullCabinet(C) :- 5 <= #count { T : cabinetTOthing(C,T), thing(T) }, cabinet(C).
fullRoom(R) :- room(R), 4 <= #sum { S,C : roomTOcabinetSize(R,C,S), cabinetDomain(C) }.
assignedThing(T) :- cabinetTOthing(_,T).
assignedCabinet(C) :- roomTOcabinet(_,C).
personTOcabinet(P,C) :- personTOthing(P,T), cabinetTOthing(C,T).
otherPersonTOcabinet(P,C) :- personTOcabinet(P2,C), person(P), P!=P2.
otherPersonTOroom(P,R)    :- roomTOcabinet(R,C), personTOcabinet(P2,C), person(P), P!=P2.

% ===== ausiliari SAME-TUPLE per il DSL nativo (__heuristic) =====
% positivi (corpo implicito = stessa tupla del target)
cabLongCand(C,T)  :- cabinetDomain(C), thingLong(T).
cabShortCand(C,T) :- cabinetDomain(C), thingShort(T).
roomCabCand(R,C)  :- roomDomain(R), cabinet(C).
cabThingDom(C,T)  :- cabinetDomain(C), thing(T).
legacyCabinetThingLong(C,T)  :- legacyCabinetThing(C,T), thingLong(T).
legacyCabinetThingShort(C,T) :- legacyCabinetThing(C,T), thingShort(T).
% negativi precompilati sulla tupla del target (per __n_<pred>)
cabFull(C,T)         :- cabinetDomain(C), thing(T), fullCabinet(C).
thingAssignedAt(C,T) :- cabinetDomain(C), thing(T), assignedThing(T).
cabOtherPerson(C,T)  :- cabinetDomain(C), thing(T), personTOthing(P,T), otherPersonTOcabinet(P,C).
roomFull(R,C)        :- roomDomain(R), cabinet(C), fullRoom(R).
cabAssignedAt(R,C)   :- roomDomain(R), cabinet(C), assignedCabinet(C).
roomOtherPerson(R,C) :- roomDomain(R), cabinet(C), personTOcabinet(P,C), otherPersonTOroom(P,R).

% ===== euristiche LAZY CLINGO (lc) - DSL nativo __heuristic =====
__heuristic(__target(reuseCabinet),      legacyCabinet,            __weight(6), __priority(4), __semantics(clingo), __modifier(true)).
__heuristic(__target(reuseRoom),         legacyRoom,               __weight(5), __priority(4), __semantics(clingo), __modifier(true)).
__heuristic(__target(reuseCabinetThing), legacyCabinetThingLong,   __weight(4), __priority(4), __semantics(clingo), __modifier(true)).
__heuristic(__target(reuseCabinetThing), legacyCabinetThingShort,  __weight(3), __priority(4), __semantics(clingo), __modifier(true)).
__heuristic(__target(reuseRoomCabinet),  legacyRoomCabinet,        __weight(2), __priority(4), __semantics(clingo), __modifier(true)).
__heuristic(__target(reusePersonRoom),   legacyPersonRoom,         __weight(1), __priority(4), __semantics(clingo), __modifier(true)).
__heuristic(__target(cabinetTOthing), cabLongCand,  __n_cabFull, __n_thingAssignedAt, __n_cabOtherPerson, __weight(__sub(MC, self)), __priority(3), __semantics(clingo), __modifier(true)) :- maxCabinet(MC).
__heuristic(__target(cabinetTOthing), cabShortCand, __n_cabFull, __n_thingAssignedAt, __n_cabOtherPerson, __weight(__sub(MC, self)), __priority(2), __semantics(clingo), __modifier(true)) :- maxCabinet(MC).
__heuristic(__target(roomTOcabinet),  roomCabCand,  __n_roomFull, __n_cabAssignedAt, __n_roomOtherPerson, __weight(__sub(MR, self)), __priority(1), __semantics(clingo), __modifier(true)) :- maxRoom(MR).
__heuristic(__target(cabinet),        cabinetDomain, __weight(1), __priority(0), __semantics(clingo), __modifier(false)).
__heuristic(__target(room),           roomDomain,    __weight(1), __priority(0), __semantics(clingo), __modifier(false)).
__heuristic(__target(cabinetTOthing), cabThingDom,   __weight(1), __priority(0), __semantics(clingo), __modifier(false)).
__heuristic(__target(roomTOcabinet),  roomCabCand,   __weight(1), __priority(0), __semantics(clingo), __modifier(false)).

#show cabinetTOthing/2.
#show roomTOcabinet/2.
