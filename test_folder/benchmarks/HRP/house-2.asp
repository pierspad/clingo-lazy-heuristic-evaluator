% HRP instance generato automaticamente (gen_hrp_instances.py)
% persone=2 cose/persona=4 slack=1 legacy_fraction=0.0

% --- persone, cose, possesso ---
person(1..2).
thing(1..8).
personTOthing(1,1..4).
personTOthing(2,5..8).

% --- cose lunghe (cabinet alto) ---
thingLong(4). thingLong(8).

% --- dominio cabinet/stanze (con slack) ---
cabinetDomainNew(1..3).
roomDomainNew(1..3).

% --- legacy configuration (riconfigurazione) ---
% (legacy vuoto: configurazione pura)

