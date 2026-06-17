% HRP instance generato automaticamente (gen_hrp_instances.py)
% persone=6 cose/persona=4 slack=2 legacy_fraction=0.5

% --- persone, cose, possesso ---
person(1..6).
thing(1..24).
personTOthing(1,1..4).
personTOthing(2,5..8).
personTOthing(3,9..12).
personTOthing(4,13..16).
personTOthing(5,17..20).
personTOthing(6,21..24).

% --- cose lunghe (cabinet alto) ---
thingLong(4). thingLong(8). thingLong(12). thingLong(16). thingLong(20). thingLong(24).

% --- dominio cabinet/stanze (con slack) ---
cabinetDomainNew(1..8).
roomDomainNew(1..8).

% --- legacy configuration (riconfigurazione) ---
legacyCabinet(1). legacyRoom(1). legacyRoomCabinet(1,1).
legacyCabinetThing(1,1..4).
legacyCabinet(2). legacyRoom(2). legacyRoomCabinet(2,2).
legacyCabinetThing(2,5..8).
legacyCabinet(3). legacyRoom(3). legacyRoomCabinet(3,3).
legacyCabinetThing(3,9..12).

