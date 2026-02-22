% quando un bin è considerato usato
used(Bin) :- assign(_, Bin).

% assegna ogni oggetto a esattamente un bin
1 { assign(Item, Bin) : bin(Bin) } 1 :- item(Item).

% la somma dei pesi in una scatola non deve superarne la capacità
:- bin(Bin), #sum { Weight,Item : assign(Item,Bin), weight(Item,Weight) } > capacity.

% minimizza il numero di scatole usate
#minimize { 1,Bin : used(Bin) }.