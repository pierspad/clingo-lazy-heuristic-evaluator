% HRP instance generato automaticamente (gen_hrp_instances.py)
% persone=16 cose/persona=4 slack=2 legacy_fraction=0.5

% --- persone, cose, possesso ---
person(1..16).
thing(1..64).
personTOthing(1,1..4).
personTOthing(2,5..8).
personTOthing(3,9..12).
personTOthing(4,13..16).
personTOthing(5,17..20).
personTOthing(6,21..24).
personTOthing(7,25..28).
personTOthing(8,29..32).
personTOthing(9,33..36).
personTOthing(10,37..40).
personTOthing(11,41..44).
personTOthing(12,45..48).
personTOthing(13,49..52).
personTOthing(14,53..56).
personTOthing(15,57..60).
personTOthing(16,61..64).

% --- cose lunghe (cabinet alto) ---
thingLong(4). thingLong(8). thingLong(12). thingLong(16). thingLong(20). thingLong(24). thingLong(28). thingLong(32). thingLong(36). thingLong(40). thingLong(44). thingLong(48). thingLong(52). thingLong(56). thingLong(60). thingLong(64).

% --- dominio cabinet/stanze (con slack) ---
cabinetDomainNew(1..18).
roomDomainNew(1..18).

% --- legacy configuration (riconfigurazione) ---
legacyCabinet(1). legacyRoom(1). legacyRoomCabinet(1,1).
legacyCabinetThing(1,1..4).
legacyCabinet(2). legacyRoom(2). legacyRoomCabinet(2,2).
legacyCabinetThing(2,5..8).
legacyCabinet(3). legacyRoom(3). legacyRoomCabinet(3,3).
legacyCabinetThing(3,9..12).
legacyCabinet(4). legacyRoom(4). legacyRoomCabinet(4,4).
legacyCabinetThing(4,13..16).
legacyCabinet(5). legacyRoom(5). legacyRoomCabinet(5,5).
legacyCabinetThing(5,17..20).
legacyCabinet(6). legacyRoom(6). legacyRoomCabinet(6,6).
legacyCabinetThing(6,21..24).
legacyCabinet(7). legacyRoom(7). legacyRoomCabinet(7,7).
legacyCabinetThing(7,25..28).
legacyCabinet(8). legacyRoom(8). legacyRoomCabinet(8,8).
legacyCabinetThing(8,29..32).

