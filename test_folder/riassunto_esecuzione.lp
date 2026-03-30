



Answer Set Programming (ASP) è un framework di rappresentazione della conoscenza e ragionamento dichiarativo basato sulla logica del primo ordine. Il paradigma di calcolo dei moderni sistemi ASP, come Clingo, si articola in due fasi principali. Inizialmente, il grounder (Gringo) trasforma le descrizioni del primo ordine in logica proposizionale, costruendo l'universo di Herbrand ed eliminando le variabili. Successivamente, il programma proposizionale equivalente viene risolto dal solver (Clasp), il quale opera sullo spazio di ricerca tramite tecniche avanzate come il CDNL (Conflict-Driven Clause Learning) per generare le soluzioni .

Un problema critico di questo processo è che istanze di grandi dimensioni non possono essere groundate in tempi e spazi di memoria accettabili. Questa esplosione combinatoria, nota come grounding bottleneck, si può notare persino quando si utilizzano euristiche domain-specific che incorporano aggregati.  
La semantica degli aggregati in ASP prevede che essi siano valutati esclusivamente rispetto a un assegnamento di verità completo. Poiché Gringo non può conoscere a priori quali atomi risulteranno veri durante la ricerca, è costretto a generare preventivamente tutte le possibili combinazioni di valori per le variabili presenti nel corpo dell'euristica.
L'euristica che viene aggiunta con lo scopo di velocizzare il tempo di solving finisce per saturare la RAM e rendere il processo di grounding impraticabile o il processo di solving inefficiente a causa dell'enorme spazio di ricerca generato.

Nel balanced sum problem, come definito nel paper di Comploi-Taupe, l'obiettivo è che la differenza in valore assoluto della somma degli elementi contenuti in due insiemi sia uguale a 1.
Immaginando di dover distribuire equamente i numeri da 1 a 3 tra due insiemi, b e c, con la condizione che ogni numero può essere assegnato solo a uno dei due insiemi. Per indirizzare il solver, è utile massimizzare l'assegnazione a un insieme valutando dinamicamente la somma dell'altro. Usando la sintassi nativa, scriveremmo:

#heuristic b(X): x(X), not c(X), S = #sum{Y : c(Y)}. [X@S]
#heuristic c(X): x(X), not b(X), S = #sum{Y : b(Y)}. [X@S]

è importante specificare che non è l'aggregato in se a generare un esplosione combinatoria.
Se venisse usato in un normale vincolo logico, gringo lo tradurrebbe in un weight constraint.
il problema sorge quando viene usato in un'euristica, poiché allo stato dell'arte, gli aggregati in ASP sono valutati esclusivamente rispetto a un assegnamento completo di valori di verità, il che implica che il loro valore non può mutare dinamicamente durante il solving. Contestualmente, la direttiva euristica esige che il livello di priorità, rappresentato dalla variabile S nel costrutto [X@S], sia un numero intero concreto e definito già durante la fase di grounding. Tuttavia, Gringo opera prima dell'inizio della ricerca e non ha modo di prevedere l'assegnamento parziale, ovvero non sa quanti e quali atomi c(Y) o b(Y) diventeranno veri.

Di conseguenza, non potendo calcolare un valore univoco per S, il grounder è costretto a coprire ogni possibile scenario futuro per preservare la correttezza logica del programma.  Per farlo, genera una direttiva euristica proposizionale separata per ogni singolo valore intero che l'aggregato potrebbe ipoteticamente restituire. Gringo grounderebbe quindi l'euristica secondo il seguente pattern prima ancora di avviare la fase di solving, esaurendo rapidamente la memoria RAM con regole superflue:

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


Per rendere quindi il processo più efficiente l'obiettivo è far si che il calcolo dell'aggregato venga effettuato a runtime valutando esclusivamente l'assegnazione parziale corrente, evitando così di dover pre-calcolare tutte le possibili combinazioni di valori per le variabili presenti nel corpo dell'euristica.

Il programma viene passato a Clingo, ma invece di far groundare a Gringo le euristiche secondo il pattern classico, queste vengono codificate come template strutturali, ovvero fatti proposizionali statici della forma:

__heuristic(TargetPred, ...argomenti flessibili...).

Il primo argomento è sempre il predicato target. Gli argomenti successivi sono in ordine libero
e vengono classificati automaticamente dal parser C++:
  - atomo semplice (es. x)         → body positivo
  - prefisso __n_ (es. __n_c)     → body negativo (not c(X))
  - "self"                         → weight = valore del dominio
  - numero intero                  → weight costante
  - __sum(p), __count(p), etc.     → aggregato per la priority
  - __w_sum(p), __w_count(p), etc. → aggregato per il weight
  - "true" / "false" / "sign"      → segno dell'euristica

Questo fa sì che Gringo includa nel programma proposizionale una singola riga per ogni template euristico, senza espandere le variabili di dominio, generando quindi invece soltanto:

__heuristic(b, x, __n_c, self, __sum(c), true).
__heuristic(c, x, __n_b, self, __sum(b), true).



I fatti generati vengono successivamente interpretati dinamicamente dal propagatore custom durante la fase di solving in Clasp. 
Il propagatore monitora l'assegnazione parziale corrente e istanzia l'euristica (calcolandone peso e priorità) in tempo reale, unicamente quando i letterali trigger nel corpo diventano veri. 


alcuni esempi:


% 1. Caso base con variabile e singolo letterale positivo
#heuristic b(X) : x(X). [1@2, true]                  
% --------------
__heuristic(b, x, 1, 2, true).

% 2. Caso Non-Ground completo (Valutato dinamicamente dal propagatore)
% Il peso usa il valore stesso della variabile X ('self')
#heuristic b(X) : x(X), not c(X). [X@1, sign]
% --------------
__heuristic(b, x, __n_c, self, 1, sign).

% 3. Caso con letterali multipli nel corpo
% Il propagatore C++ ora supporta N body positivi e M body negativi direttamente,
% senza bisogno di predicati ausiliari!
#heuristic c(X) : a(X), b(X), not d(X). [5@2, false]
% --------------
__heuristic(c, a, b, __n_d, 5, 2, false).

% 4. Caso con Aggregati Dinamici (PrioritySpec dinamica)
#heuristic b(X) : x(X), not c(X). [X@S, true] % dove S è la somma corrente di c
% --------------
__heuristic(b, x, __n_c, self, __sum(c), true).

% 5. L'ordine degli argomenti (dopo il primo) è irrilevante:
__heuristic(b, __n_c, x, self, __sum(c), true).
% è equivalente a:
__heuristic(b, x, __n_c, self, __sum(c), true).

% 6. Caso con Aggregato Dinamico per il WEIGHT
% Il peso viene calcolato a runtime con __w_sum, __w_count, __w_min, __w_max
#heuristic b(X) : x(X), not c(X). [S1@S2, true] % S1=count(c), S2=sum(c)
% --------------
__heuristic(b, x, __n_c, __w_count(c), __sum(c), true).