


Asp è un linguaggio di programmazione logica che consente di esprimere problemi complessi in modo dichiarativo. 

In clingo:
Il funzionamento di asp si basa su due fasi principali: grounding e solving. Durante la fase di grounding, viene costruito l'universo di herbrand, ovvero l'insieme di tutte le possibili istanze di regole e fatti basati sui termini presenti nel programma dal grounder gringo

Una volta che l'universo di herbrand è stato costruito, l'insieme di regole e fatti viene trasformato in un programma proposizionale, (ovvero un programma senza variabili) che viene poi tradotto in booleano e risolto da clasp, il solver di clingo.

Uno dei problemi principali di questo processo è che, in alcune situazioni, per via della natura o della formalizzazione del problema, il processo di grounding può portare alla generazione di un numero esponenziale di regole e fatti, causando un consumo eccessivo di memoria e rendendo il processo di solving impraticabile.

il problema del groudning avviene anche quando si utilizzano euristiche per guidare la ricerca, come ad esempio l'uso di aggregati nei corpi delle regole euristiche.

Nel baalnced sum proble immaginando di dover distribuire equamente i nueri da 1 a 3 tra due insiemi, b e c, con la condizione che ogni numero può essere assegnato solo a uno dei due insiemi. L'obiettivo è massimizzare la somma dei numeri assegnati all'insieme b, tenendo conto che la somma dei numeri in c deve essere il più possibile vicina a quella in b.

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

quindi la logica sarebbe che:

si passa il programma non ground a clingo (o gringo?) e lui ne fa il grounding, ma invece di groundare le euristiche secondo il pattern classico, le trasforma in regole del tipo __heuristic(<term>, <weight>, <priority>, <sign>) :- <body>.

questo fa si che gringo groundi una singola istanza dell'atomo heuristic per ogni possibile scelta, invece dell'instanziare tutte le possibili combinazioni di valori per le variabili presenti nel corpo dell'euristica, evitando così l'esplosione combinatoria (lato euristiche)

quell'atomo groundato viene poi valutato dinamicamente dal propagatore custom durante la fase di solving, permettendo di calcolare il peso e la priorità dell'euristica in base all'assegnazione parziale corrente, senza dover pre-calcolare tutte le possibili combinazioni di valori per le variabili presenti nel corpo dell'euristica.










