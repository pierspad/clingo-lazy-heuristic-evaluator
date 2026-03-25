

nel baalnced sum proble immaginando di dover distribuire equamente i nueri da 1 a 3 tra due insiemi, b e c, con la condizione che ogni numero può essere assegnato solo a uno dei due insiemi. L'obiettivo è massimizzare la somma dei numeri assegnati all'insieme b, tenendo conto che la somma dei numeri in c deve essere il più possibile vicina a quella in b.

useremmo queste euristiche per guidare la ricerca.

#heuristic b(x): x(X), not c(X), S = #sum{Y : c(Y)}, [X@S].

#heuristic c(x): x(X), not b(X), S = #sum{Y : b(Y)}, [X@S].

il problema di queste euristiche è che gringo le grounderebbe secondo questo pattern ancor prima di iniziare la fase di solving finendo per riempire la ram con tutte le possibili regole


% prima euristica
#heuristic b(1):not c(1),#sum{1:c(1);2:c(2);3:c(3)}=0.[1@0,true]
#heuristic b(1):not c(1),#sum{1:c(1);2:c(2);3:c(3)}=1.[1@1,true]
#heuristic b(1):not c(1),#sum{1:c(1);2:c(2);3:c(3)}=2.[1@2,true]
#heuristic b(1):not c(1),#sum{1:c(1);2:c(2);3:c(3)}=3.[1@3,true]
#heuristic b(1):not c(1),#sum{1:c(1);2:c(2);3:c(3)}=4.[1@4,true]
#heuristic b(1):not c(1),#sum{1:c(1);2:c(2);3:c(3)}=5.[1@5,true]
#heuristic b(1):not c(1),#sum{1:c(1);2:c(2);3:c(3)}=6.[1@6,true]

#heuristic b(2):not c(2),#sum{1:c(1);2:c(2);3:c(3)}=0.[2@0,true]
#heuristic b(2):not c(2),#sum{1:c(1);2:c(2);3:c(3)}=1.[2@1,true]
#heuristic b(2):not c(2),#sum{1:c(1);2:c(2);3:c(3)}=2.[2@2,true]
#heuristic b(2):not c(2),#sum{1:c(1);2:c(2);3:c(3)}=3.[2@3,true]
#heuristic b(2):not c(2),#sum{1:c(1);2:c(2);3:c(3)}=4.[2@4,true]
#heuristic b(2):not c(2),#sum{1:c(1);2:c(2);3:c(3)}=5.[2@5,true]
#heuristic b(2):not c(2),#sum{1:c(1);2:c(2);3:c(3)}=6.[2@6,true]

#heuristic b(3):not c(3),#sum{1:c(1);2:c(2);3:c(3)}=0.[3@0,true]
#heuristic b(3):not c(3),#sum{1:c(1);2:c(2);3:c(3)}=1.[3@1,true]
#heuristic b(3):not c(3),#sum{1:c(1);2:c(2);3:c(3)}=2.[3@2,true]
#heuristic b(3):not c(3),#sum{1:c(1);2:c(2);3:c(3)}=3.[3@3,true]
#heuristic b(3):not c(3),#sum{1:c(1);2:c(2);3:c(3)}=4.[3@4,true]
#heuristic b(3):not c(3),#sum{1:c(1);2:c(2);3:c(3)}=5.[3@5,true]
#heuristic b(3):not c(3),#sum{1:c(1);2:c(2);3:c(3)}=6.[3@6,true]


% seconda euristica
#heuristic c(1):not b(1),#sum{1:b(1);2:b(2);3:b(3)}=0.[1@0,true]
#heuristic c(1):not b(1),#sum{1:b(1);2:b(2);3:b(3)}=1.[1@1,true]
#heuristic c(1):not b(1),#sum{1:b(1);2:b(2);3:b(3)}=2.[1@2,true]
#heuristic c(1):not b(1),#sum{1:b(1);2:b(2);3:b(3)}=3.[1@3,true]
#heuristic c(1):not b(1),#sum{1:b(1);2:b(2);3:b(3)}=4.[1@4,true]
#heuristic c(1):not b(1),#sum{1:b(1);2:b(2);3:b(3)}=5.[1@5,true]
#heuristic c(1):not b(1),#sum{1:b(1);2:b(2);3:b(3)}=6.[1@6,true]

#heuristic c(2):not b(2),#sum{1:b(1);2:b(2);3:b(3)}=0.[2@0,true]
#heuristic c(2):not b(2),#sum{1:b(1);2:b(2);3:b(3)}=1.[2@1,true]
#heuristic c(2):not b(2),#sum{1:b(1);2:b(2);3:b(3)}=2.[2@2,true]
#heuristic c(2):not b(2),#sum{1:b(1);2:b(2);3:b(3)}=3.[2@3,true]
#heuristic c(2):not b(2),#sum{1:b(1);2:b(2);3:b(3)}=4.[2@4,true]
#heuristic c(2):not b(2),#sum{1:b(1);2:b(2);3:b(3)}=5.[2@5,true]
#heuristic c(2):not b(2),#sum{1:b(1);2:b(2);3:b(3)}=6.[2@6,true]

#heuristic c(3):not b(3),#sum{1:b(1);2:b(2);3:b(3)}=0.[3@0,true]
#heuristic c(3):not b(3),#sum{1:b(1);2:b(2);3:b(3)}=1.[3@1,true]
#heuristic c(3):not b(3),#sum{1:b(1);2:b(2);3:b(3)}=2.[3@2,true]
#heuristic c(3):not b(3),#sum{1:b(1);2:b(2);3:b(3)}=3.[3@3,true]
#heuristic c(3):not b(3),#sum{1:b(1);2:b(2);3:b(3)}=4.[3@4,true]
#heuristic c(3):not b(3),#sum{1:b(1);2:b(2);3:b(3)}=5.[3@5,true]
#heuristic c(3):not b(3),#sum{1:b(1);2:b(2);3:b(3)}=6.[3@6,true]


l'obiettivo è far si che il calcolo dell'aggregato avvenga a runtime valutando esclusivamente l'assegnazione parziale corrente 


avendo implementato un propagatore custom riscriviamo le euristiche in questo modo:

invece di scrivere:

#heuristic <term> : <body>. [<weight>@<priority>, <sign>]

scriviamo:

__heuristic(<term>, <weight>, <priority>, <sign>) :- <body>.

alcuni esempi:



% 1. Caso base (Senza corpo, l'euristica si applica sempre)
#heuristic a. [1@2, true]                  
% --------------
__heuristic(a, 1, 2, true).

% 2. Caso con singolo letterale nel corpo
#heuristic c : a. [1@1, true]              
% --------------
__heuristic(c, 1, 1, true) :- a.

% 3. Caso con letterali multipli nel corpo (possono essere N letterali, positivi o negativi)
#heuristic c : a, b, not d. [5@2, false]
% --------------
__heuristic(c, 5, 2, false) :- a, b, not d.

% 4. Caso con variabili (Non-Ground, valutabile dinamicamente dal tuo propagatore in futuro)
#heuristic b(X) : x(X), not c(X). [X@1, sign]
% --------------
__heuristic(b(X), X, 1, sign) :- x(X), not c(X).





