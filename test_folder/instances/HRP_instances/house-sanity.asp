% HRP instance generato automaticamente (gen_hrp_instances.py)
% persone=1 cose/persona=2 slack=1 legacy_fraction=0.0

% --- persone, cose, possesso ---
person(1..1).
thing(1..2).
personTOthing(1,1..2).

% --- cose lunghe (cabinet alto) ---
thingLong(2).

% --- dominio cabinet/stanze (con slack) ---
cabinetDomainNew(1..2).
roomDomainNew(1..2).

% --- legacy configuration (riconfigurazione) ---
% (legacy vuoto: configurazione pura)

