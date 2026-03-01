% quando un bin è considerato usato
used(Bin) :- assign(_, Bin).

% assegna ogni oggetto a esattamente un bin
1 { assign(Item, Bin) : bin(Bin) } 1 :- item(Item).

% CORREZIONE: La capacità viene letta dal fatto capacity/2
:- bin(Bin), capacity(Bin, Cap), #sum { Weight,Item : assign(Item,Bin), weight(Item,Weight) } > Cap.

% minimizza il numero di scatole usate
#minimize { 1,Bin : used(Bin) }.

#show assign/2.
#show used/1.