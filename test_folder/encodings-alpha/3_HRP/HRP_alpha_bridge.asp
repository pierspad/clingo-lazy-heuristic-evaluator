%% ============================================================
%% Raccordo istanze suite -> HRP_alpha.asp. SOLO RINOMINE.
%%
%% Le istanze house-*.asp di questa suite (prodotte da
%% tools/gen_hrp_instances.py) scrivono la configurazione legacy con
%% predicati piatti, uno per tipo di oggetto:
%%
%%     legacyCabinet(1).  legacyRoom(1).  legacyRoomCabinet(1,1).
%%     legacyCabinetThing(1,1..4).
%%
%% L'encoding degli autori legge le stesse identiche informazioni come
%% TERMINI dentro un unico predicato legacyConfig/1:
%%
%%     legacyConfig(cabinet(1)).  legacyConfig(room(1)).
%%     legacyConfig(roomTOcabinet(1,1)).
%%     legacyConfig(cabinetTOthing(1,1)). ...
%%
%% Stessi fatti, ortografia diversa. Questo file e' l'adattatore fra le
%% due: sette regole, tutte della forma "questo nome si scrive cosi'".
%% Non aggiunge un solo vincolo, una sola scelta, un solo peso: se lo
%% leggi cercando modellazione non ne trovi, ed e' voluto — l'intero
%% valore del confronto con Alpha sta nell'usare l'encoding degli autori
%% intatto (v. l'intestazione di HRP_alpha.asp).
%%
%% L'alternativa sarebbe stata far emettere entrambe le ortografie al
%% generatore di istanze, ma le istanze sono CONDIVISE con gli encoding
%% clingo: aggiungerci fatti cambierebbe il loro grounding e i numeri
%% gia' misurati non sarebbero piu' confrontabili con quelli nuovi.
%%
%% Passato ad Alpha come secondo -i, insieme a HRP_alpha.asp: il
%% runscript elenca due <encoding> con lo stesso encoding_tag="hrp" e
%% benchmark-tool li accoda entrambi (v. runscript/runscript.py, gli
%% encoding per tag sono un set che finisce tutto in {encodings}).
%% ============================================================

%% --- configurazione legacy: piatta -> termine dentro legacyConfig/1 ---
legacyConfig(cabinet(C))          :- legacyCabinet(C).
legacyConfig(room(R))             :- legacyRoom(R).
legacyConfig(cabinetTOthing(C,T)) :- legacyCabinetThing(C,T).
legacyConfig(roomTOcabinet(R,C))  :- legacyRoomCabinet(R,C).

%% --- persone, cose e possesso ---
%% Nelle istanze degli autori person/thing/personTOthing arrivano SOLO
%% dentro legacyConfig/1 (v. righe 74-76 di HRP_alpha.asp, che da li' le
%% riderivano); nelle istanze di questa suite sono fatti diretti. Le
%% rimappiamo comunque, per due motivi:
%%   1) legacyConfig(personTOthing/2) e' l'ingrediente da cui HRP_alpha.asp
%%      DERIVA legacyConfig(personTOroom/2) (sua riga 34) — senza, il
%%      riuso delle assegnazioni persona-stanza non verrebbe mai proposto
%%      e l'euristica perderebbe la sua ultima componente. E' l'analogo
%%      esatto di "legacyPersonRoom(P,R) :- personTOthing(P,T),
%%      legacyCabinetThing(C,T), legacyRoomCabinet(R,C)." negli encoding
%%      clingo HRP_*.lp di questa suite;
%%   2) person/1 e thing/1 cosi' sono definiti per entrambe le vie, e
%%      l'encoding resta corretto anche se un domani un'istanza smettesse
%%      di dichiararli in chiaro. Sono no-op sugli atomi derivati: i fatti
%%      diretti dell'istanza li producono gia'.
legacyConfig(person(P))           :- person(P).
legacyConfig(thing(T))            :- thing(T).
legacyConfig(personTOthing(P,T))  :- personTOthing(P,T).
