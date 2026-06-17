% ============================================================
% HRP - GROUND ALPHA (ga): port NAIVE dell'euristica Alpha di Romero 1
% (house_alpha_2021-02-04.asp) messa a ground in clingo COSI' COM'E'.
%
% Caratteristiche del port naive (didattico):
%   - mantiene le priorita' per-livello [w@4] .. [w@1] dell'originale.
%     ATTENZIONE: in clingo la @priority di un #heuristic discrimina solo
%     fra modifiche allo STESSO atomo, NON impone un ordine globale fra
%     atomi diversi (quello lo da' il peso). Quindi l'ordinamento globale
%     reuse>fill-cabinet>fill-room NON viene rispettato come in Alpha:
%     e' esattamente il motivo per cui la variante 'gc' appiattisce i
%     livelli nel peso.
%   - mantiene i 'not' su informazione PARZIALE (not fullCabinet,
%     not assignedThing, not otherPersonTOcabinet, ...). In clingo a ground
%     'not p' significa 'p e' falso', non 'p non ancora vero' (semantica
%     Alpha): quindi questi letterali si attivano al momento sbagliato.
%     La semantica Alpha fedele e' catturata solo dalla variante lazy 'la'.
%
% Esegui con: --heuristic=Domain
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

% ===== euristiche GA (port naive di Alpha, ground in clingo) =====
#heuristic reuseCabinet(C)        : legacyCabinet(C). [6@4, true]
#heuristic reuseRoom(R)           : legacyRoom(R). [5@4, true]
#heuristic reuseCabinetThing(C,T) : legacyCabinetThing(C,T),     thingLong(T). [4@4, true]
#heuristic reuseCabinetThing(C,T) : legacyCabinetThing(C,T), not thingLong(T). [3@4, true]
#heuristic reuseRoomCabinet(R,C)  : legacyRoomCabinet(R,C). [2@4, true]
#heuristic reusePersonRoom(P,R)   : legacyPersonRoom(P,R). [1@4, true]
#heuristic cabinetTOthing(C,T) : cabinetDomain(C), not fullCabinet(C), not assignedThing(T), personTOthing(P,T), not otherPersonTOcabinet(P,C), maxCabinet(MC), thingLong(T),     W=MC-C. [W@3, true]
#heuristic cabinetTOthing(C,T) : cabinetDomain(C), not fullCabinet(C), not assignedThing(T), personTOthing(P,T), not otherPersonTOcabinet(P,C), maxCabinet(MC), thingShort(T),    W=MC-C. [W@2, true]
#heuristic roomTOcabinet(R,C)  : roomDomain(R), not fullRoom(R), cabinet(C), not assignedCabinet(C), personTOcabinet(P,C), not otherPersonTOroom(P,R), maxRoom(MR), W=MR-R. [W@1, true]
#heuristic cabinet(C)          : cabinetDomain(C). [1, false]
#heuristic room(R)             : roomDomain(R). [1, false]
#heuristic cabinetTOthing(C,T) : cabinetDomain(C), thing(T). [1, false]
#heuristic roomTOcabinet(R,C)  : roomDomain(R), cabinet(C). [1, false]
