% HRP instance generato automaticamente (gen_hrp_instances.py)
% persone=4 cose/persona=4 slack=2 legacy_fraction=0.5

% --- persone, cose, possesso ---
person(1..4).
thing(1..16).
personTOthing(1,1..4).
personTOthing(2,5..8).
personTOthing(3,9..12).
personTOthing(4,13..16).

% --- cose lunghe (cabinet alto) ---
thingLong(4). thingLong(8). thingLong(12). thingLong(16).

% --- dominio cabinet/stanze (con slack) ---
cabinetDomainNew(1..6).
roomDomainNew(1..6).

% --- legacy configuration (riconfigurazione) ---
legacyCabinet(1). legacyRoom(1). legacyRoomCabinet(1,1).
legacyCabinetThing(1,1..4).
legacyCabinet(2). legacyRoom(2). legacyRoomCabinet(2,2).
legacyCabinetThing(2,5..8).

