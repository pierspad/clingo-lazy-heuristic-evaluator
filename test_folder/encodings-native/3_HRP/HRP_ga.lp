% ============================================================
% HRP - GROUND ALPHA (ga): simulazione ground-and-solve della semantica
% Alpha, coerente con BSP_ga / PUP_ga e SIMMETRICA a HRP_gc.
%
% Principio (cardine BSP): da gc ad ga si applica la trasformazione
% minima e controllata ->
%   1) si lascia cadere l'intero sotto-goal NEGATIVO su stato parziale
%      (in Alpha 'not p' = "p non ancora vero"; in ground clingo 'not p'
%      = "p falso", non esprimibile -> si elimina, come 'not c(X)' in BSP);
%   2) se il peso contiene un aggregato, l'uguaglianza '=' diventa un bound
%      '<='/'>=' su dominio statico (pattern sum_value di BSP / value di PUP).
%      In HRP il peso e' STATICO (W=MC-C), quindi il passo 2 NON si applica:
%      non c'e' aggregato da convertire e l'unica mossa e' il passo 1.
%   3) i PESI restano APPIATTITI [W,true] IDENTICI a gc (niente @priority:
%      in clingo @priority arbitra solo modifiche allo STESSO atomo, non
%      l'ordine globale -> va appiattito nel peso, cfr. INTENT.txt).
%
% Risultato: gc e ga condividono lo stesso scheletro positivo e gli stessi
% pesi, e differiscono SOLO per i 'not' (come 'lc' vs 'la' differiscono solo
% per clingo_not vs alpha_not). La semantica Alpha FEDELE su stato parziale
% resta catturata unicamente dalla variante lazy 'la'.
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

% ===== aux per appiattimento livelli (identico a HRP_gc) =====
maxCabinetId(M) :- M = #max{ C : cabinetDomain(C) }.
maxRoomId(M)    :- M = #max{ R : roomDomain(R) }.
levelMul(LM)    :- LM = MC + MR + 10, maxCabinetId(MC), maxRoomId(MR).

% ===== euristiche GA (alpha-sim ground, BSP-consistente) =====
% Rispetto a HRP_gc cadono SOLO i 'not' su stato parziale (not fullCabinet,
% not assignedThing, not otherPerson..., e i loro binder orfani
% personTOthing/personTOcabinet): in ground clingo 'not p' = "p falso", che
% NON e' la semantica Alpha ("p non ancora vero"). Non essendoci aggregati
% nel peso (W=MC-C statico), non c'e' alcun '='->'<=' da convertire come in
% BSP/PUP: l'unica mossa alpha-sim disponibile e' lasciar cadere il
% sotto-goal negativo. Resta un ordinamento statico (reuse > cabinet id
% minore, lunghe prima > stanze). I PESI sono APPIATTITI [W,true], IDENTICI
% a gc: gc e ga differiscono ESCLUSIVAMENTE per i 'not'.
#heuristic reuseCabinet(C)        : legacyCabinet(C), levelMul(LM), W = 6 + 4*LM. [W, true]
#heuristic reuseRoom(R)           : legacyRoom(R), levelMul(LM), W = 5 + 4*LM. [W, true]
#heuristic reuseCabinetThing(C,T) : legacyCabinetThing(C,T), thingLong(T),  levelMul(LM), W = 4 + 4*LM. [W, true]
#heuristic reuseCabinetThing(C,T) : legacyCabinetThing(C,T), thingShort(T), levelMul(LM), W = 3 + 4*LM. [W, true]
#heuristic reuseRoomCabinet(R,C)  : legacyRoomCabinet(R,C), levelMul(LM), W = 2 + 4*LM. [W, true]
#heuristic reusePersonRoom(P,R)   : legacyPersonRoom(P,R), levelMul(LM), W = 1 + 4*LM. [W, true]
#heuristic cabinetTOthing(C,T) : cabinetDomain(C), thingLong(T),  maxCabinet(MC), levelMul(LM), W = (MC-C) + 3*LM. [W, true]
#heuristic cabinetTOthing(C,T) : cabinetDomain(C), thingShort(T), maxCabinet(MC), levelMul(LM), W = (MC-C) + 2*LM. [W, true]
#heuristic roomTOcabinet(R,C)  : roomDomain(R), cabinet(C), maxRoom(MR), levelMul(LM), W = (MR-R) + 1*LM. [W, true]
#heuristic cabinet(C)          : cabinetDomain(C). [1, false]
#heuristic room(R)             : roomDomain(R). [1, false]
#heuristic cabinetTOthing(C,T) : cabinetDomain(C), thing(T). [1, false]
#heuristic roomTOcabinet(R,C)  : roomDomain(R), cabinet(C). [1, false]
