% quando un bin è considerato usato
used(Bin) :- assign(_, Bin).

% assegna ogni oggetto a esattamente un bin
1 { assign(Item, Bin) : bin(Bin) } 1 :- item(Item).

% minimizza il numero di scatole usate
#minimize { 1,Bin : used(Bin) }.


#show assign/2.
#show used/1.