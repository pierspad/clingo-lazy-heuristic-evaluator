



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
  - atomo semplice (es. x)                    → body positivo
  - prefisso __n_ (es. __n_c)                → body negativo (not c(X))
  - __bind(var, __agg(pred))                  → binding variabile → aggregato
  - __weight(expr)                             → espressione per il peso
  - __priority(expr)                           → espressione per la priorità
  - "true" / "false" / "sign"                  → segno dell'euristica

Le espressioni (expr) supportate sono:
  - numero intero                              → costante (es. 5)
  - self                                       → valore del dominio (es. X in b(X))
  - variabile (nome da __bind)                 → valore corrente dell'aggregato legato
  - __add(a, b)                                → somma di due espressioni
  - __sub(a, b)                                → sottrazione
  - __mul(a, b)                                → moltiplicazione

Questo fa sì che Gringo includa nel programma proposizionale una singola riga per ogni template euristico, senza espandere le variabili di dominio, generando quindi invece soltanto:

__heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).
__heuristic(c, x, __n_b, __bind(s, __sum(b)), __weight(self), __priority(s), true).



I fatti generati vengono successivamente interpretati dinamicamente dal propagatore custom durante la fase di solving in Clasp. 
Il propagatore monitora l'assegnazione parziale corrente e istanzia l'euristica (calcolandone peso e priorità) in tempo reale, unicamente quando i letterali trigger nel corpo diventano veri. 


alcuni esempi:


% 1. Caso base con costanti fisse per peso e priorità
#heuristic b(X) : x(X). [1@2, true]                  
% --------------
__heuristic(b, x, __weight(1), __priority(2), true).

% 2. Caso con peso = valore del dominio (self)
#heuristic b(X) : x(X), not c(X). [X@1, sign]
% --------------
__heuristic(b, x, __n_c, __weight(self), __priority(1), sign).

% 3. Caso con letterali multipli nel corpo
#heuristic c(X) : a(X), b(X), not d(X). [5@2, false]
% --------------
__heuristic(c, a, b, __n_d, __weight(5), __priority(2), false).

% 4. Caso con Aggregato Dinamico (priorità da aggregato)
#heuristic b(X) : x(X), not c(X). [X@S, true] % dove S è la somma corrente di c
% --------------
__heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).

% 5. L'ordine degli argomenti (dopo il primo) è irrilevante:
__heuristic(b, __n_c, x, __bind(s, __sum(c)), __priority(s), __weight(self), true).
% è equivalente a:
__heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).

% 6. Caso con peso e priorità ENTRAMBI da aggregati diversi
#heuristic b(X) : x(X), not c(X). [S1@S2, true] % S1=count(c), S2=sum(c)
% --------------
__heuristic(b, x, __n_c, __bind(s, __sum(c)), __bind(k, __count(c)), __weight(k), __priority(s), true).

% 7. NOVITÀ: Espressioni matematiche complesse
% Weight = S + 1, Priority = S * 10
__heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(__add(s, 1)), __priority(__mul(s, 10)), true).

% 8. Combinazione di self con aggregato
% Weight = self + somma_di_c, Priority = somma_di_c
__heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(__add(self, s)), __priority(s), true).

% 9. Stessa variabile usata sia in weight che in priority
% Weight = S, Priority = S + 1
__heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(s), __priority(__add(s, 1)), true).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 10) Architettura AST (Abstract Syntax Tree) per __weight/__priority
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

La sintassi flessibile di __weight(expr) e __priority(expr) non viene gestita
come semplice parsing testuale durante la fase di scelta. In init_lazy_mode,
il propagatore analizza i termini Clingo e costruisce un AST polimorfico
basato sull'interfaccia Expression. Ogni forma sintattica viene trasformata in
un nodo tipizzato: costanti numeriche in ConstExpr, self in SelfExpr,
variabili legate da __bind in VarExpr, e operatori binari (__add/__sub/__mul)
in BinOpExpr con due sottoalberi. Questa compilazione avviene una sola volta
in fase di inizializzazione.

Durante decide, per ogni istanza lazy attiva viene costruito un environment
(mappa nome->valore) che contiene il valore del dominio corrente (__self__) e
i valori correnti degli aggregati risolti dalle local_vars. La valutazione di
weight_expr e priority_expr avviene quindi per visita dell'albero, partendo dai
nodi foglia e propagando i risultati verso i nodi interni. In questo modo non
si effettua alcun parsing di stringhe a runtime: il costo per decisione e'
deterministico e legato solo alla dimensione dell'espressione gia' compilata,
con overhead costante rispetto alla ricerca CDNL.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 11) Gestione del backtracking CDNL (metodo undo)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

La correttezza del propagatore non dipende solo dalla propagazione in avanti,
ma anche dalla capacita' di ripristinare esattamente lo stato quando Clasp
esegue backjump/backtracking dopo un conflitto. Questo e' gestito nel metodo
undo, che riceve i literal rimossi dall'assegnamento e aggiorna in senso
inverso tutte le strutture incrementali.

Per gli aggregati, SumState e CountState applicano l'inversa aritmetica
(remove) rispetto all'aggiornamento effettuato in propagate (add):
somma e conteggio tornano al valore precedente in O(1). Per __min e __max,
non e' sufficiente invertire con una singola operazione numerica; MinState e
MaxState mantengono quindi un multiset implicito (mappa valore->occorrenze)
che consente di rimuovere correttamente il contributo del literal annullato e
di recuperare il nuovo estremo valido senza ricalcolare l'aggregato da zero.
In parallelo, undo elimina anche le istanze lazy create dai trigger che non
sono piu' veri, mantenendo allineate active_body_lits e lazy_targets_ con lo
stato effettivo del solver.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 12) Valutazione empirica (benchmark.sh + graphs.py)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

La validazione sperimentale e' stata condotta con benchmark.sh, confrontando la
codifica standard (#heuristic con aggregati groundati dal front-end) contro la
variante lazy con template __heuristic/N e valutazione runtime nel propagatore.
I risultati, salvati in test-results/results.csv e visualizzati da graphs.py,
mostrano un miglioramento sistematico sia in tempo sia in memoria al crescere
di N (10..100).

In media, la variante lazy riduce il tempo di esecuzione del 44.15% e ottiene
uno speedup medio di 1.74x (1.82x a N=100: 112.81s -> 62.00s). Sul fronte
memoria, la RSS massima si riduce mediamente del 18.20%, con un picco di
riduzione del 28.80% (N=40). A N=100, il consumo passa da 3746.45 MB a
3270.48 MB, con un risparmio assoluto di circa 476 MB. Questi numeri
confermano che il lazy grounding delle euristiche attenua il grounding
bottleneck e rende il comportamento molto piu' scalabile su istanze grandi,
evitando l'esplosione preventiva delle combinazioni aggregate.