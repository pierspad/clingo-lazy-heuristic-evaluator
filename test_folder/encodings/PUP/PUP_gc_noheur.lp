
elem(z,Z) :- zone2sensor(Z,D).
elem(s,D) :- zone2sensor(Z,D).

{ assign(U,T,X) } :- elem(T,X), comUnit(U).

% every comUnit can have a maximum of two zones and two sensors
% every zone must be assignet to exactly one comUnit
:- assign(U,T,X1), assign(U,T,X2), assign(U,T,X3), X1<X2, X2<X3.
:- assign(U1,T,X), assign(U2,T,X), U1<U2.
atLeastOneUnit(T,X):- assign(_,T,X).
:- elem(T,X), not atLeastOneUnit(T,X).

% if comUnit U handles a zone and comUnit P (P!=U) handles a sensor and
% in the real world the sensor belongs to that zone then we call
% the comUnit as "Partners" 
% no more than 2 partners are allowed
partnerunits(U,P) :- assign(U,z,Z), assign(P,s,D), zone2sensor(Z,D), U!=P.
partnerunits(U,P) :- partnerunits(P,U).
:- partnerunits(U,P1), partnerunits(U,P2), partnerunits(U,P3), P1<P2, P2<P3.
	

assigned_zone_unit(Z, U) :- assign(U,z,Z).
assigned_zone_unit(S, U) :- assign(U,s,S).
