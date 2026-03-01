

% assegna ogni oggetto a esattamente un bin
1 { assign(Item, Bin) : bin(Bin) } 1 :- item(Item).

% quando un bin è considerato usato
used(Bin) :- assign(_, Bin).

% un bin non può essere usato se la somma dei pesi degli oggetti assegnati supera la capacità
:- bin(Bin), capacity(Bin, Cap), #sum { Weight,Item : assign(Item,Bin), weight(Item,Weight) } > Cap.

% minimizza il numero di scatole usate
#minimize { 1,Bin : used(Bin) }.

#show assign/2.
#show used/1.