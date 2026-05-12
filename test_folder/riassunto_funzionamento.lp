
# Link to the pup instances and encodings
https://github.com/tilmanni/Alpha/tree/domspec_heuristics_extended_prolog/Evaluation/PUP


clingo-modified/libclingo/src/heuristic_propagator.cc
clingo-modified/libclingo/src/heuristic_parser.cc
clingo-modified/libclingo/clingo/heuristic_symbol.hh
clingo-modified/libclingo/clingo/heuristic_types.hh
clingo-modified/libclingo/clingo/heuristic_aggregate.hh
clingo-modified/libclingo/clingo/heuristic_parser.hh
clingo-modified/libclingo/clingo/heuristic_propagator.hh
clingo-modified/libclingo/tests/heuristic_propagator.cc

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 1) Introduzione al problema del grounding bottleneck con euristiche e aggregati
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Answer Set Programming (ASP) è un framework di rappresentazione della conoscenza e ragionamento dichiarativo basato sulla logica del primo ordine. Il paradigma di calcolo dei moderni sistemi ASP, come Clingo, si articola in due fasi principali. Inizialmente, il grounder (Gringo) trasforma le descrizioni del primo ordine in logica proposizionale, costruendo l'universo di Herbrand ed eliminando le variabili. Successivamente, il programma proposizionale equivalente viene risolto dal solver (Clasp), il quale opera sullo spazio di ricerca tramite tecniche avanzate come il CDNL (Conflict-Driven Clause Learning) per generare le soluzioni.

Un problema critico di questo processo è che istanze di grandi dimensioni non possono essere groundate in tempi e spazi di memoria accettabili. Questa esplosione combinatoria, nota come grounding bottleneck, si può notare persino quando si utilizzano euristiche domain-specific che incorporano aggregati.

In Clingo, i pesi e le priorità ([W@P]) di un'euristica devono essere risolti dal grounder come costanti intere statiche prima che il solving inizi. Se W o P dipendono dal risultato di un aggregato (come S), Gringo non ha un valore costante da inserire nell'istruzione per il solver. Di conseguenza, l'unico modo per preservare la logica è istanziare una direttiva euristica separata per ogni singolo valore intero che l'aggregato può generare. L'euristica che viene aggiunta con lo scopo di velocizzare il tempo di solving finisce per saturare la RAM e rendere il processo di grounding impraticabile o il processo di solving inefficiente a causa dell'enorme spazio di ricerca generato.

Nel balanced sum problem, come definito nel paper di Comploi-Taupe, l'obiettivo è suddividere i numeri da $1$ a $n$ in due insiemi disgiunti, b e c, in modo tale che la differenza in valore assoluto tra la somma dei loro elementi sia al massimo 1. Immaginando di dover distribuire equamente i numeri, per indirizzare il solver è utile massimizzare l'assegnazione a un insieme valutando dinamicamente la somma dell'altro.

Usando la sintassi nativa, scriveremmo:

#heuristic b(X): x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]
#heuristic c(X): x(X), not b(X), S = #sum{Y : b(Y)}. [X@S, true]

È importante specificare che non è l'aggregato in sé a generare automaticamente un'esplosione combinatoria. Se lo stesso aggregato compare in un normale vincolo logico con bound già determinabili, per esempio:


b(1..4)

#const min_val = 2.
#const max_val = 5.

:- not min_val <= #sum{Y : b(Y)} <= max_val.

Gringo non deve produrre una regola distinta per ogni possibile valore della somma. Dopo il grounding, gli elementi dell'aggregato diventano una lista di letterali pesati:

b(1):-#delayed(1).
b(2):-#delayed(1).
b(3):-#delayed(1).
b(4):-#delayed(1).
#delayed(1) <=> not 2<=#sum{1:b(1);2:b(2);3:b(3);4:b(4)}<=5

e il vincolo viene compilato in una o più strutture lineari gestite da Clasp come weight constraint.


Il problema nasce quando il valore dell'aggregato viene usato per costruire il peso o la priorità di una direttiva `#heuristic`. Nel formato interno passato al solver, una direttiva euristica nativa non contiene un'espressione dinamica del tipo "la somma corrente di c"; contiene un target, un modificatore, una condizione e due interi già fissati, cioè bias/peso e priority. Quindi, nel costrutto `[X@S]`, la variabile `S` deve essere risolta dal grounder prima che la ricerca inizi.

Dal punto di vista dichiarativo, il valore di un aggregato ASP è definito rispetto a un'interpretazione; dal punto di vista implementativo, Clasp può propagare aggregati con bound statici su assegnamenti parziali tramite weight constraint. Quello che manca nella semantica euristica nativa è un canale per leggere, a ogni decisione, il valore corrente di un aggregato e usarlo come priorità variabile.

Di conseguenza, quando `S = #sum{Y : c(Y)}` serve a valorizzare `[X@S]`, Gringo non può lasciare `S` simbolico fino al solving. Per preservare la semantica standard, deve coprire a priori ogni valore che l'aggregato potrebbe restituire, generando una direttiva euristica proposizionale separata per ciascun valore intero possibile. Gringo grounderebbe quindi l'euristica secondo il seguente pattern prima ancora di avviare la fase di solving, saturando rapidamente la memoria con regole che rappresentano scenari futuri alternativi:

% prima euristica
x(1).
x(2).
x(3).
c(1):-not b(1).
c(2):-not b(2).
c(3):-not b(3).
b(1):-not c(1).
b(2):-not c(2).
b(3):-not c(3).
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
sumC(0):-#sum{1:c(1);2:c(2);3:c(3)}=0.
sumC(1):-#sum{1:c(1);2:c(2);3:c(3)}=1.
sumC(2):-#sum{1:c(1);2:c(2);3:c(3)}=2.
sumC(3):-#sum{1:c(1);2:c(2);3:c(3)}=3.
sumC(4):-#sum{1:c(1);2:c(2);3:c(3)}=4.
sumC(5):-#sum{1:c(1);2:c(2);3:c(3)}=5.
sumC(6):-#sum{1:c(1);2:c(2);3:c(3)}=6.
sumB(0):-#sum{1:b(1);2:b(2);3:b(3)}=0.
sumB(1):-#sum{1:b(1);2:b(2);3:b(3)}=1.
sumB(2):-#sum{1:b(1);2:b(2);3:b(3)}=2.
sumB(3):-#sum{1:b(1);2:b(2);3:b(3)}=3.
sumB(4):-#sum{1:b(1);2:b(2);3:b(3)}=4.
sumB(5):-#sum{1:b(1);2:b(2);3:b(3)}=5.
sumB(6):-#sum{1:b(1);2:b(2);3:b(3)}=6.
:-sumC(0),sumB(2).
:-sumC(0),sumB(3).
:-sumC(0),sumB(4).
:-sumC(0),sumB(5).
:-sumC(0),sumB(6).
:-sumC(1),sumB(3).
:-sumC(1),sumB(4).
:-sumC(1),sumB(5).
:-sumC(1),sumB(6).
:-sumC(2),sumB(0).
:-sumC(2),sumB(4).
:-sumC(2),sumB(5).
:-sumC(2),sumB(6).
:-sumC(3),sumB(0).
:-sumC(3),sumB(1).
:-sumC(3),sumB(5).
:-sumC(3),sumB(6).
:-sumC(4),sumB(0).
:-sumC(4),sumB(1).
:-sumC(4),sumB(2).
:-sumC(4),sumB(6).
:-sumC(5),sumB(0).
:-sumC(5),sumB(1).
:-sumC(5),sumB(2).
:-sumC(5),sumB(3).
:-sumC(6),sumB(0).
:-sumC(6),sumB(1).
:-sumC(6),sumB(2).
:-sumC(6),sumB(3).
:-sumC(6),sumB(4).


Per rendere il processo più efficiente, le euristiche vengono tradotte come template strutturali, ovvero fatti proposizionali statici della forma:

__heuristic(__target(TargetPred), ...argomenti flessibili...).

Il predicato target viene dichiarato esplicitamente con __target(TargetPred). L'ordine degli argomenti non è rilevante e vengono classificati automaticamente dal parser C++:
- __target(pred)                             → predicato target
- atomo semplice (es. x)                    → body positivo
- __body(pred, __match(...), __bind_arg(...)) → body positivo con mapping esplicito
- prefisso __n_ (es. __n_c)                → body negativo (not c(X))
- __bind(var, __agg(pred, idx?, filters...)) → binding variabile → aggregato (l'indice è opzionale solo se non si usano filtri)
- __weight(expr)                             → espressione per il peso
- __priority(expr)                           → espressione per la priorità
- "true" / "false" / "sign"                  → segno dell'euristica
- __semantics(alpha|clingo)                  → semantica di attivazione dei body

Le espressioni (expr) supportate sono:
- numero intero                              → costante (es. 5)
- self                                       → valore del dominio MVP: primo argomento numerico del target (es. X in b(X))
- variabile (nome da __bind o __bind_arg)    → valore corrente dell'aggregato legato o argomento estratto dal body
- __add(a, b)                                → somma di due espressioni
- __sub(a, b)                                → sottrazione
- __mul(a, b)                                → moltiplicazione



Convenzione semantica implementativa per aggregati vuoti:

`__sum` e `__count` restituiscono naturalmente 0 quando nessun letterale sorgente è attivo. Anche `__min` e `__max`, nell'implementazione corrente, restituiscono 0 quando l'insieme osservato è vuoto. In particolare, le strutture `MinState` e `MaxState` mantengono una `std::map<int,int>` delle occorrenze attive e il metodo `result()` ritorna 0 se tale mappa è vuota. Questa non va letta come la definizione matematica pura di minimo o massimo dell'insieme vuoto, che spesso richiederebbe valori sentinella come +infinito o -infinito: è una convenzione locale del propagatore lazy, scelta per mantenere totale la valutazione degli AST aritmetici di peso e priorità ed evitare overflow o comportamenti indefiniti nel percorso decisionale.

Questo fa sì che Gringo includa nel programma proposizionale una singola riga per ogni template euristico, senza espandere le variabili di dominio, generando quindi invece soltanto:


x(1).
x(2).
x(3).
c(1):-not b(1).
c(2):-not b(2).
c(3):-not b(3).
b(1):-not c(1).
b(2):-not c(2).
b(3):-not c(3).
__heuristic(__target(b),x,__n_c,__bind(s,__sum(c,0)),__weight(self),__priority(s),true,__semantics(clingo)).
__heuristic(__target(c),x,__n_b,__bind(s,__sum(b,0)),__weight(self),__priority(s),true,__semantics(clingo)).
sumC(0):-#sum{1:c(1);2:c(2);3:c(3)}=0.
sumC(1):-#sum{1:c(1);2:c(2);3:c(3)}=1.
sumC(2):-#sum{1:c(1);2:c(2);3:c(3)}=2.
sumC(3):-#sum{1:c(1);2:c(2);3:c(3)}=3.
sumC(4):-#sum{1:c(1);2:c(2);3:c(3)}=4.
sumC(5):-#sum{1:c(1);2:c(2);3:c(3)}=5.
sumC(6):-#sum{1:c(1);2:c(2);3:c(3)}=6.
sumB(0):-#sum{1:b(1);2:b(2);3:b(3)}=0.
sumB(1):-#sum{1:b(1);2:b(2);3:b(3)}=1.
sumB(2):-#sum{1:b(1);2:b(2);3:b(3)}=2.
sumB(3):-#sum{1:b(1);2:b(2);3:b(3)}=3.
sumB(4):-#sum{1:b(1);2:b(2);3:b(3)}=4.
sumB(5):-#sum{1:b(1);2:b(2);3:b(3)}=5.
sumB(6):-#sum{1:b(1);2:b(2);3:b(3)}=6.
:-sumC(0),sumB(2).
:-sumC(0),sumB(3).
:-sumC(0),sumB(4).
:-sumC(0),sumB(5).
:-sumC(0),sumB(6).
:-sumC(1),sumB(3).
:-sumC(1),sumB(4).
:-sumC(1),sumB(5).
:-sumC(1),sumB(6).
:-sumC(2),sumB(0).
:-sumC(2),sumB(4).
:-sumC(2),sumB(5).
:-sumC(2),sumB(6).
:-sumC(3),sumB(0).
:-sumC(3),sumB(1).
:-sumC(3),sumB(5).
:-sumC(3),sumB(6).
:-sumC(4),sumB(0).
:-sumC(4),sumB(1).
:-sumC(4),sumB(2).
:-sumC(4),sumB(6).
:-sumC(5),sumB(0).
:-sumC(5),sumB(1).
:-sumC(5),sumB(2).
:-sumC(5),sumB(3).
:-sumC(6),sumB(0).
:-sumC(6),sumB(1).
:-sumC(6),sumB(2).
:-sumC(6),sumB(3).
:-sumC(6),sumB(4).



Per semplicità la traduzione è standardizzata e delegata allo script `test_folder/tools/asp_heuristic_converter.py`. Il tool legge il file tramite l'AST di `clingo.ast`, intercetta i nodi `ASTType.Heuristic` e ricostruisce una descrizione strutturata della direttiva originale: target, body positivi, body negativi, assegnamenti aggregati, espressione del peso, espressione della priorità e modificatore (`true`, `false`, `sign`).

A quel punto può emettere quattro varianti:

- `la`: template lazy con semantica Alpha;
- `lc`: template lazy con semantica Clingo, marcato da `__semantics(clingo)`;
- `aux`: riscrittura ground-and-solve con predicati ausiliari e `#heuristic` nativa;
- `la-aux`: predicato ausiliario più template lazy.

Il punto essenziale è che il file lazy non prova a far calcolare l'aggregato a Gringo. L'aggregato viene codificato come termine non interpretato `__sum(...)`, `__count(...)`, `__min(...)` o `__max(...)`; il parser C++ lo riconosce durante `init` e costruisce una chiave aggregata runtime. I fatti generati vengono successivamente interpretati dal propagatore custom durante il solving in Clasp. Il propagatore monitora l'assegnamento parziale corrente, mantiene gli `AggregateState` incrementali e aggiorna peso/priorità dei candidati euristici quando cambiano i letterali rilevanti.


// TODO forse andrebbe spiegato in dettaglio come funziona il self ? e se funziona esattamente come in clingo o se ha delle peculiarità

Esempi di traduzione:

% 1. Caso base: peso e priorità costanti.
#heuristic b(X) : x(X). [1@2, true]
% diventa
__heuristic(__target(b), x, __weight(1), __priority(2), true).

% `x` è un body positivo implicito: il propagatore cercherà gli atomi x(V) e li abbinerà ai target b(V) con la stessa tupla numerica.


% 2. Peso uguale al valore del dominio.
#heuristic b(X) : x(X), not c(X). [X@1, sign]
% diventa
__heuristic(__target(b), x, __n_c, __weight(self), __priority(1), sign).

% `__n_c` rappresenta `not c(X)` sulla stessa tupla del target. Il modificatore `sign` segue il segno del fallback scelto dal solver.


% 3. Più body positivi sulla stessa tupla.
#heuristic c(X) : a(X), b(X), not d(X). [5@2, false]
% diventa
__heuristic(__target(c), a, b, __n_d, __weight(5), __priority(2), false).

% Il candidato c(V) è attivo solo quando a(V) e b(V) sono veri; il controllo su d(V) dipende dalla semantica scelta: in semantica Alpha basta che d(V) non sia vero, in semantica Clingo deve essere esplicitamente falso.


% 4. BSP: priorità dinamica data dalla somma corrente dell'altro insieme.
#heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]
% diventa, nella forma prodotta dal converter:
__heuristic(__target(b), x, __n_c,
            __bind(s, __sum(c, 0)),
            __weight(self), __priority(s), true).

% `__sum(c, 0)` significa: osserva gli atomi c(Y) e aggrega l'argomento 0. La variabile locale `s` viene letta da `__priority(s)`. La forma manuale `__sum(c)` è accettata per predicati unari: il parser usa l'ultimo argomento numerico disponibile come valore aggregato.


% 5. Peso e priorità entrambi da aggregati diversi.
#heuristic b(X) : x(X), not c(X),
                  K = #count{Y : c(Y)},
                  S = #sum{Y : c(Y)}. [K@S, true]
% diventa
__heuristic(__target(b), x, __n_c,
            __bind(k, __count(c, 0)),
            __bind(s, __sum(c, 0)),
            __weight(k), __priority(s), true).


% 6. Body con mapping esplicito e variabile estratta dal body.
#heuristic choose(X) : body(X,W). [W@1, true]
% diventa
__heuristic(__target(choose),
            __body(body, __match(0, 0), __bind_arg(w, 1)),
            __weight(w), __priority(1), true).

% `__match(0,0)` dice che l'argomento 0 di body deve coincidere con l'argomento 0 del target choose. `__bind_arg(w,1)` salva il secondo argomento di body nella variabile locale w, poi usata nel peso. Se piu' istanze del predicato di body possono generare lo stesso target con valori diversi per una variabile legata, il propagatore costruisce partial match separati. Le combinazioni in cui la stessa variabile locale riceve due valori incompatibili vengono scartate da `merge_variable_values`, mentre i partial match coerenti producono candidati distinti.


% 7. PUP: aggregato filtrato rispetto a un argomento del target.
#heuristic assigned_zone_unit(Z,U) :
        assignable_zone_unit(Z,U),
        Assigned_zones_unit = #count{ZN : assigned_zone_unit(ZN,U)}.
        [Assigned_zones_unit * 10@1, true]
% diventa schematicamente
__heuristic(__target(assigned_zone_unit), assignable_zone_unit,
            __bind(assigned_zones_unit,
                   __count(assigned_zone_unit, 0, __filter(1, 1))),
            __weight(__mul(assigned_zones_unit, 10)),
            __priority(1), true).

% Qui il target è assigned_zone_unit(Z,U). L'aggregato osserva gli atomi assigned_zone_unit(ZN,Ucorrente): aggrega l'argomento 0, ma filtra l'argomento sorgente 1 imponendo che sia uguale all'argomento target 1. Nel parser corrente, quando si usano filtri è necessario indicare anche l'indice dell'argomento aggregato.


% 8. Filtri con offset: U1 = U - 1 e U2 = U + 1.
#heuristic assigned_zone_unit(Z,U) :
        assignable_zone_unit(Z,U),
        N1 = #max{N : num_sensors_on_unit(N,U-1)},
        N2 = #max{N : num_sensors_on_unit(N,U+1)}.
        [6 - (N1 + N2)@1, true]
% diventa schematicamente
__heuristic(__target(assigned_zone_unit), assignable_zone_unit,
            __bind(n1, __max(num_sensors_on_unit, 0, __filter(1, 1, -1))),
            __bind(n2, __max(num_sensors_on_unit, 0, __filter(1, 1, 1))),
            __weight(__sub(6, __add(n1, n2))),
            __priority(1), true).

% L'offset è applicato al valore della tupla target: `__filter(1,1,-1)` seleziona sorgenti con argomento 1 uguale a U-1, mentre `__filter(1,1,1)` seleziona sorgenti con argomento 1 uguale a U+1.


% 9. Espressioni aritmetiche nel peso e nella priorità.
__heuristic(__target(b), x, __n_c,
            __bind(s, __sum(c, 0)),
            __weight(__add(self, s)),
            __priority(__mul(s, 10)), true).

% Il parser costruisce un AST aritmetico tipizzato: numeri, self, variabili legate da __bind/__bind_arg, e operatori binari __add, __sub, __mul. Non avviene parsing testuale durante l'hot path del solver.


% 10. Stesso template con semantica Clingo.
__heuristic(__target(b), x, __n_c,
            __bind(s, __sum(c, 0)),
            __weight(self), __priority(s), true,
            __semantics(clingo)).

% In questa modalità `not c(X)` richiede c(X) falso, non semplicemente libero; inoltre un aggregato viene usato solo quando tutti i suoi atomi sorgente rilevanti sono assegnati.


% 11. L'ordine degli argomenti è irrilevante.
__heuristic(__target(b), __n_c, x,
            __bind(s, __sum(c, 0)),
            __priority(s), __weight(self), true).
% è equivalente a:
__heuristic(x, __priority(s), true, __target(b),
            __bind(s, __sum(c, 0)), __n_c, __weight(self)).



%% ------------------------------------------------------

Il propagatore implementato è `HeuristicPropagator`, che eredita da `Clingo::Heuristic`. 
Questa interfaccia estende `Clingo::Propagator`: oltre a `init`, `propagate` e `undo`, espone il metodo `decide`, cioè il punto in cui il solver chiede al propagatore se vuole suggerire il prossimo letterale di decisione.

1) `init`: parsing dei template e costruzione dei candidati.

All'inizio `init` pulisce tutte le strutture interne:

`aggregate_states_`, `watched_atoms_`, `rule_templates_`, 
`candidates_`, `candidate_queue_`, `candidate_refresh_lits_`, 
`aggregate_candidates_`, `aggregate_source_lits_` e `registered_watches_`. 

Poi scansiona gli atomi simbolici del programma ground e:

Se non trova alcun fatto `__heuristic(...)`, il propagatore rimane inattivo.
Se invece trova template lazy (__heuristic), entra in `init_lazy_mode`. 

In `init_lazy_mode` avvengono quattro passaggi.

Primo: 
`parse_lazy_heuristic_templates(atoms)` trasforma i fatti `__heuristic/N` in `HeuristicRuleTemplate`. 
Il parser classifica gli argomenti in target, body positivi, body negativi, binding aggregati, peso, priorità, segno e semantica. 
Le espressioni aritmetiche non rimangono stringhe: vengono compilate in un piccolo AST (`ArithmeticExpression`) che verrà valutato durante la ricerca.

Secondo: 
`build_lazy_predicate_literal_map` costruisce una mappa:

Predicato -> tupla numerica -> solver literal

Per esempio, se nel programma ground esistono 
`x(1)` = slit 35, 
`x(2)` = slit 36
`b(1)` = slit 102
`b(2)` = slit 103

la mappa conterrà voci del tipo
Clingo::literal_t slit = pred_lit_map[Clingo::Id("x")][AtomKey{{1}}]; // Restituisce 35
Clingo::literal_t slit = pred_lit_map[Clingo::Id("b")][AtomKey{{2}}]; // Restituisce 103

Il propagatore considera solo atomi funzione con argomenti numerici, perché `AtomKey` è una tupla di interi.

Terzo: 
`register_lazy_body_triggers` materializza i `CandidateState`. 
Un template non è ancora una singola decisione concreta: rappresenta una famiglia di possibili target. Per ogni atomo target ground compatibile, il propagatore prova ad abbinare i body positivi:

- body implicito, come `x`, significa stessa tupla del target;
- body esplicito, come `__body(body, __match(0,0), __bind_arg(w,1))`, costruisce un indice sui body e permette mapping non banali;
- body negativo, come `__n_c`, viene tradotto nel literal di `c` sulla stessa tupla del target, quando esiste.

Ogni candidato memorizza:

- `rule_idx`: quale template lo ha generato;
- `target_lit`: il literal solver del target, per esempio `b(3)`;
- `self_value`: il primo valore numerico della tupla target;
- `tuple_values`: tutta la tupla target;
- `body_var_values`: variabili estratte da `__bind_arg`;
- `pos_body_lits` e `neg_body_lits`;
- `aggregate_bindings`, cioè le variabili locali collegate a un aggregato runtime.

Durante questa fase il propagatore registra anche i watch necessari a sapere quando un candidato può cambiare stato: target positivo e negativo, body positivi, body negativi e, dove serve, il negativo dei sorgenti aggregati per la semantica Clingo.

Quarto: `register_lazy_aggregate_watches` prepara gli aggregati incrementali.
Per ogni binding come:

__bind(s, __sum(c, 0))

il propagatore cerca tutti gli atomi ground `c(...)`, estrae il valore numerico da aggregare e costruisce una `RuntimeAggregateKey`. La chiave non contiene solo operatore e predicato, ma anche gli eventuali valori filtrati.
Per esempio:

__count(assigned_zone_unit, 0, __filter(1, 1))

crea stati separati per ciascun valore corrente di `U`, perché il filtro chiede di contare solo gli atomi `assigned_zone_unit(ZN,Ucorrente)`.

Ogni sorgente aggregata viene registrata in `watched_atoms_` con il valore che contribuisce all'aggregato. Se un literal sorgente è già vero al momento dell'inizializzazione, il suo valore viene aggiunto subito allo stato aggregato. Infine `refresh_all_candidates(init.assignment())` valuta una prima volta tutti i candidati e inserisce nella `candidate_queue_` quelli già applicabili.

2) `propagate`: aggiornamento incrementale durante la BCP.

Dopo `init`, il solver entra nel normale ciclo CDNL. Durante la Boolean Constraint Propagation, quando un watched literal diventa vero, Clasp invoca `propagate(control, changes)`. Un propagatore può usare questa callback per aggiungere nogood; questa implementazione non lo fa. Qui `propagate` serve a mantenere sincronizzate le strutture euristiche con l'assegnamento parziale.

Per ogni literal `lit` in `changes`, il propagatore fa due cose.

Se `lit` è una sorgente aggregata presente in `watched_atoms_`, ogni contributo associato viene applicato allo stato corrispondente:

state->add(value)

Per `__sum` questo incrementa il totale; per `__count` incrementa il contatore; per `__min` e `__max` aggiorna una `std::map<int,int>` che mantiene le occorrenze dei valori attivi. Subito dopo, il propagatore richiama `refresh_candidates_for_aggregate(runtime_key, assignment)`, perché tutti i candidati che dipendono da quell'aggregato potrebbero avere cambiato peso o priorità.

In ogni caso, anche se `lit` non è una sorgente aggregata, il propagatore chiama `refresh_candidates_for_literal(lit, assignment)`. Questo aggiorna i candidati che dipendono dal target, da un body positivo o da un body negativo toccato da quel literal.

Il punto cruciale è che gli `AggregateState` non sono un'informazione morta: vengono letti dentro `compute_candidate_entry`. Quando un candidato viene aggiornato, il propagatore costruisce l'ambiente delle variabili (`var_env`), legge per ogni binding il valore corrente con:

state->result()

e poi valuta gli AST di `__priority(...)` e `__weight(...)`. Il risultato è una
`CandidateQueueEntry` con:

- priorità corrente;
- peso corrente;
- literal target;
- identificativo del candidato.

Questa entry viene inserita in `candidate_queue_`, ordinata per priorità decrescente, poi peso decrescente, poi literal e id candidato per stabilizzare i pareggi. Quindi il valore salvato negli aggregati viene effettivamente usato per decidere l'ordine dei prossimi branching literal. La stabilizzazione dei pareggi non è solo estetica: `CandidateQueueEntryLess` usa `target_lit` e poi `candidate_id` come criteri finali di ordinamento. A parità di priorità, peso e seed casuale di Clasp, il solver percorre quindi lo stesso albero CDNL, proprietà importante per rendere riproducibili i benchmark e confrontare in modo corretto varianti di encoding diverse.

3) `compute_candidate_entry`: controllo della semantica del template.

Prima di mettere un candidato in coda, `compute_candidate_entry` verifica che sia davvero applicabile nello stato corrente:

- il target deve essere ancora `Free`;
- tutti i body positivi devono essere `True`;
- ogni body negativo deve essere soddisfatto secondo la semantica del template;
- ogni chiave aggregata deve essere valida rispetto alla tupla target.

La differenza tra semantica Alpha e semantica Clingo è implementata qui. In semantica Alpha, un body negativo `not a(X)` è soddisfatto quando `a(X)` non è vero: quindi è valido sia se `a(X)` è falso sia se è ancora libero. In semantica Clingo, invece, `not a(X)` è soddisfatto solo quando `a(X)` è esplicitamente falso.

Anche gli aggregati cambiano comportamento. In semantica Alpha si usa il valore incrementale corrente: gli atomi ancora liberi semplicemente non contribuiscono. In semantica Clingo, prima di leggere `state->result()`, il propagatore controlla `aggregate_source_lits_`: se esiste anche un solo sorgente aggregato ancora `Free`, il candidato non viene considerato applicabile. Questo emula una lettura più prudente dell'aggregato, coerente con l'idea di non usare un valore parziale come se fosse già definitivo.

4) `decide`: scelta del prossimo literal.

Quando la propagazione raggiunge un fixpoint e il solver deve aprire un nuovo ramo dell'albero di ricerca, Clasp chiama:

decide(thread_id, assignment, fallback)

Il metodo guarda il primo elemento di `candidate_queue_`, cioè il candidato migliore secondo priorità e peso. Prima di restituirlo, però, lo rivalida: ricostruisce una `CandidateQueueEntry` con `compute_candidate_entry`. Se il candidato non è più applicabile, viene rimosso. Se è ancora applicabile ma peso o priorità sono cambiati, viene reinserito nella posizione corretta. Solo quando l'entry in coda coincide con quella ricalcolata, `decide` restituisce il target con il segno richiesto:

- `true` restituisce `target_lit`;
- `false` restituisce `-target_lit`;
- `sign` segue il segno del `fallback` del solver.

Se la coda è vuota o nessun candidato rimane valido, `decide` restituisce `0`. In quel caso Clasp continua con la propria euristica di default.

Un dettaglio ingegneristico rilevante è che il percorso di `decide` è racchiuso in un blocco `try ... catch (...)`, e lo stesso schema è usato nelle funzioni `refresh_candidate_noexcept` chiamate durante `undo`. Se la rivalutazione lazy di un candidato fallisce, per esempio per un errore nella valutazione dell'espressione aritmetica o per un'eccezione di allocazione, il candidato viene rimosso dalla `candidate_queue_` tramite `erase_candidate_from_queue`. Nel caso di `decide`, l'eccezione viene degradata in un ritorno `0`, cioè nella scelta di non suggerire alcun literal e lasciare spazio all'euristica nativa di Clasp. Questo rende il propagatore exception-safe rispetto all'hot path: un fallimento locale della valutazione lazy non causa il crash del solving.

5) `undo`: ripristino durante backtracking e backjumping.

`undo` non viene chiamato solo dopo un conflitto, ma ogni volta che il solver deve de-assegnare literal durante backtracking o backjumping. Clasp passa al propagatore i literal che stanno uscendo dal trail. Per ciascun literal, il propagatore disfa esattamente gli aggiornamenti fatti in `propagate`:

state->remove(value)

poi aggiorna i candidati dipendenti dall'aggregato o dal literal. In questo modo `aggregate_states_` e `candidate_queue_` tornano coerenti con il nuovo assegnamento parziale, senza ricostruire tutto da zero.

6) `check`: non usato in questa implementazione.

Un propagatore può anche sovrascrivere `check` per effettuare validazioni globali o generare nogood lazy a fixpoint o su assegnamenti totali. L'attuale `HeuristicPropagator` non lo fa: la validazione dei modelli rimane affidata ai vincoli ASP dell'encoding, mentre il propagatore interviene solo sulla guidance euristica tramite `init`, `propagate`, `undo` e `decide`.


%% ------------------------------------------------------

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 10) Ottimizzazione vincolo in vincolo lineare BSP
% Dettaglio fine, per scopo di uniformità nella tesi è meglio testare gli encoding allo stesso modo
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


Il vincolo

:- not min_val <= #sum{ Y : b(Y) } <= max_val.

rappresenta un'ottimizzazione matematica applicata al Balanced Sum Problem (BSP). Nel problema originale, l'obiettivo e' suddividere i numeri da 1 a n in due insiemi disgiunti, b e c, in modo tale che la differenza in valore assoluto tra la somma dei loro elementi sia al massimo 1.

Dimostrazione formale del check.

Sia tot la somma totale dei numeri da 1 a n, calcolabile tramite la formula di Gauss:
$$tot = \frac{n(n+1)}{2}$$

Poiche' il costrutto di scelta `1 { b(X); c(X) } 1 :- x(X).` impone che ogni numero appartenga esattamente a uno dei due insiemi, vale necessariamente:
$$Sum(b) + Sum(c) = tot$$
$$Sum(c) = tot - Sum(b)$$

Il requisito del problema e': $|Sum(b) - Sum(c)| <= 1$.
Sostituendo $Sum(c)$:
$$|Sum(b) - (tot - Sum(b))| <= 1$$
$$|2 \cdot Sum(b) - tot| <= 1$$

Risolvendo il valore assoluto:
$$-1 <= 2 \cdot Sum(b) - tot <= 1$$

Aggiungendo $tot$ a tutti i membri:
$$tot - 1 <= 2 \cdot Sum(b) <= tot + 1$$

Dividendo per 2:
$$\frac{tot - 1}{2} <= Sum(b) <= \frac{tot + 1}{2}$$

Questi due estremi corrispondono matematicamente alle costanti min_val e max_val definite in testa al programma. L'aggregato `#sum{ Y : b(Y) }` calcola la somma degli elementi assegnati a b; il vincolo di integrita' scarta tutti i modelli in cui tale somma non ricade nell'intervallo valido.

Questa forma chiusa permette al grounder di precalcolare i bound statici, convertendo il controllo non lineare commentato `(SB-SC)**2 > 1` in un semplice weight constraint lineare. In questo modo Clasp deve tracciare un solo aggregato con due estremi costanti, invece di esplorare combinazioni di somme e differenze quadratiche; il risultato e' una riduzione drastica del numero di conflitti generati durante la ricerca.




% output di 
% clingo --text test_folder/encodings/BSP/BSP_gc.lp test_folder/instances/BSP_instances/BSP_range.lp

x(1).
x(2).
x(3).
#delayed(1).
#delayed(2).
#delayed(3).
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
sumC(0):-#sum{1:c(1);2:c(2);3:c(3)}=0.
sumC(1):-#sum{1:c(1);2:c(2);3:c(3)}=1.
sumC(2):-#sum{1:c(1);2:c(2);3:c(3)}=2.
sumC(3):-#sum{1:c(1);2:c(2);3:c(3)}=3.
sumC(4):-#sum{1:c(1);2:c(2);3:c(3)}=4.
sumC(5):-#sum{1:c(1);2:c(2);3:c(3)}=5.
sumC(6):-#sum{1:c(1);2:c(2);3:c(3)}=6.
sumB(0):-#sum{1:b(1);2:b(2);3:b(3)}=0.
sumB(1):-#sum{1:b(1);2:b(2);3:b(3)}=1.
sumB(2):-#sum{1:b(1);2:b(2);3:b(3)}=2.
sumB(3):-#sum{1:b(1);2:b(2);3:b(3)}=3.
sumB(4):-#sum{1:b(1);2:b(2);3:b(3)}=4.
sumB(5):-#sum{1:b(1);2:b(2);3:b(3)}=5.
sumB(6):-#sum{1:b(1);2:b(2);3:b(3)}=6.
:-sumC(0),sumB(2).
:-sumC(0),sumB(3).
:-sumC(0),sumB(4).
:-sumC(0),sumB(5).
:-sumC(0),sumB(6).
:-sumC(1),sumB(3).
:-sumC(1),sumB(4).
:-sumC(1),sumB(5).
:-sumC(1),sumB(6).
:-sumC(2),sumB(0).
:-sumC(2),sumB(4).
:-sumC(2),sumB(5).
:-sumC(2),sumB(6).
:-sumC(3),sumB(0).
:-sumC(3),sumB(1).
:-sumC(3),sumB(5).
:-sumC(3),sumB(6).
:-sumC(4),sumB(0).
:-sumC(4),sumB(1).
:-sumC(4),sumB(2).
:-sumC(4),sumB(6).
:-sumC(5),sumB(0).
:-sumC(5),sumB(1).
:-sumC(5),sumB(2).
:-sumC(5),sumB(3).
:-sumC(6),sumB(0).
:-sumC(6),sumB(1).
:-sumC(6),sumB(2).
:-sumC(6),sumB(3).
:-sumC(6),sumB(4).
#delayed(1) <=> 1<=#count{0,b(1):b(1);0,c(1):c(1)}<=1
#delayed(2) <=> 1<=#count{0,b(2):b(2);0,c(2):c(2)}<=1
#delayed(3) <=> 1<=#count{0,b(3):b(3);0,c(3):c(3)}<=1

% output di 
% clingo --text test_folder/encodings/BSP/BSP_la_co.lp test_folder/instances/BSP_instances/BSP_range.lp

__heuristic(__target(b),x,__n_c,__bind(s,__sum(c,0)),__weight(self),__priority(s),true).
__heuristic(__target(c),x,__n_b,__bind(s,__sum(b,0)),__weight(self),__priority(s),true).
x(1).
x(2).
x(3).
#delayed(1).
#delayed(2).
#delayed(3).
:-not 3<=#sum{1:b(1);2:b(2);3:b(3)}<=3.
#delayed(1) <=> 1<=#count{0,b(1):b(1);0,c(1):c(1)}<=1
#delayed(2) <=> 1<=#count{0,b(2):b(2);0,c(2):c(2)}<=1
#delayed(3) <=> 1<=#count{0,b(3):b(3);0,c(3):c(3)}<=1


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 11) Definizione formale della sintassi (__heuristic/N)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Per rendere la specifica rigorosa, la sintassi accettata dal costrutto __heuristic/N puo' essere formalizzata in EBNF come segue.

<heuristic-fact>   ::= "__heuristic(" <h-arg> {"," <h-arg>} ")."

<target>           ::= "__target(" <pred-id> ")"

<h-arg>            ::= <target>
	              | <pos-lit>
	              | <body-lit>
	              | <neg-lit>
	              | <bind>
	              | <weight>
	              | <priority>
	              | <sign>
	              | <semantics>

<pos-lit>          ::= <pred-id>
<body-lit>         ::= "__body(" <pred-id> "," <body-mapping> {"," <body-mapping>} ")"
<body-mapping>     ::= "__match(" <source-index> "," <target-index> ")"
	              | "__bind_arg(" <var-id> "," <source-index> ")"
<neg-lit>          ::= "__n_" <pred-id>

<bind>             ::= "__bind(" <var-id> "," <agg-expr> ")"
<agg-expr>         ::= "__sum(" <pred-id> ")"
              | "__sum(" <pred-id> "," <arg-index> {"," <filter>} ")"
              | "__count(" <pred-id> ")"
              | "__count(" <pred-id> "," <arg-index> {"," <filter>} ")"
              | "__min(" <pred-id> ")"
              | "__min(" <pred-id> "," <arg-index> {"," <filter>} ")"
              | "__max(" <pred-id> ")"
              | "__max(" <pred-id> "," <arg-index> {"," <filter>} ")"
<filter>           ::= "__filter(" <source-index> "," <target-index> ["," <offset>] ")"

<weight>           ::= "__weight(" <arith-expr> ")"
<priority>         ::= "__priority(" <arith-expr> ")"

<arith-expr>       ::= <int>
              | "self"
              | <var-id>
              | "__add(" <arith-expr> "," <arith-expr> ")"
              | "__sub(" <arith-expr> "," <arith-expr> ")"
              | "__mul(" <arith-expr> "," <arith-expr> ")"

<sign>             ::= "true" | "false" | "sign"
<semantics>        ::= "__semantics(alpha)" | "__semantics(clingo)"

<pred-id>          ::= identificatore predicato ASP valido
<var-id>           ::= identificatore variabile locale valida
<arg-index>        ::= indice numerico 0-based dell'argomento aggregato
<source-index>     ::= indice numerico 0-based dell'argomento del predicato aggregato
<target-index>     ::= indice numerico 0-based dell'argomento del target
<offset>           ::= intero con segno applicato al valore target
<int>              ::= intero con segno in base 10

Vincoli semantici addizionali:
1) deve essere presente esattamente un argomento <target>;
2) ogni <var-id> usata in <arith-expr> deve essere introdotta nell'ambiente di valutazione o tramite un binding di aggregato (`__bind` all'interno dello stesso fatto `__heuristic/N`) oppure estratta esplicitamente da un predicato di body tramite la direttiva `__bind_arg(var, source_idx)` all'interno di un costrutto `__body(...)`;
3) la semantica MVP di "self" coincide con il primo argomento numerico dell'atomo target nell'istanza corrente; in presenza di tuple target multi-argomento, "self" valuta specificamente il primo argomento numerico della tupla, conformemente al comportamento implementato nel parser C++;
4) l'ordine degli argomenti e' irrilevante;
5) in presenza di bind multipli sullo stesso <var-id> si applica il vincolo di unicita' (errore di parsing/inizializzazione).
6) un costrutto `__body(...)` deve contenere almeno un `__match(...)`; i `__bind_arg(...)` nello stesso body non possono ridefinire variabili già introdotte da `__bind` o da altri `__bind_arg`;
7) durante la materializzazione dei candidati, i valori estratti da `__bind_arg(...)` sono unificati per nome di variabile. Se due body match assegnano valori diversi alla stessa variabile locale, la combinazione viene scartata; se invece esistono piu' match coerenti per lo stesso target, essi generano candidati distinti;
8) per `__min` e `__max` su insieme runtime vuoto, il propagatore restituisce 0 come valore convenzionale implementativo. Questa scelta mantiene totale la valutazione delle espressioni lazy, ma non coincide con una modellazione matematica tramite +infinito o -infinito;
9) `__weight`, `__priority`, segno e `__semantics` sono opzionali nel parser corrente: i default sono rispettivamente 0, 0, `true` e `alpha`.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 16) Analisi di complessita' temporale e spaziale
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Si introducono le seguenti grandezze:
- T = numero di template __heuristic/N nel programma ground;
- B = numero medio di letterali di body monitorati per template;
- K = numero medio di bind/aggregati per template;
- E = dimensione media (nodi) degli AST di weight/priority;
- C = numero di `CandidateState` materializzati in fase di inizializzazione;
- S = numero di atomi sorgente osservati per gli aggregati runtime;
- A = numero di aggiornamenti aggregato attivati da un literal in propagate;
- U = numero di literal annullati in un singolo undo.

Tabella di confronto sintetico (per il testo tesi):

| Caratteristica | Grounding Standard | Lazy Heuristic |
| :--- | :--- | :--- |
| Dimensione programma | Esplosione combinatoria O(N^k) | O(T) template |
| Utilizzo RAM | Cresce con le istanze (fino a saturazione) | Basso e quasi costante |
| Flessibilita' euristica | Statica (valori fissati al grounding) | Dinamica (valutata su assegnamento parziale) |
| Costo decisione | Lookup su regole gia' groundate | O(E) su AST precompilato |

Confronto asintotico ad alto livello:
- Standard: il grounding delle euristiche aggregate puo' richiedere O(N^k) regole, dove k e' il numero di variabili nel corpo euristico.
- Lazy: il grounding resta O(T) sui template; il costo runtime e' O(E) per istanza attiva, con T numero template ed E dimensione AST.

Complessita' di inizializzazione (`init_lazy_mode`):
Il tempo e lo spazio dipendono dalla scansione degli atomi simbolici per la costruzione dei candidati. Sono pari a $O(C \cdot (B + K + E) + S)$, necessari per istanziare i metadati, allocare le chiavi di aggregazione e compilare gli AST. In aggiunta, `AtomKey` e `RuntimeAggregateKey` mantengono tuple di interi per il matching multi-argomento e per i filtri runtime.

Complessita' dell'hot path(`decide`):
L'implementazione non utilizza array bufferizzati per l'ambiente delle variabili, ma mappe hash basate su `Clingo::Symbol`. La coda dei candidati è mantenuta tramite un `std::set` ordinato. L'estrazione e la rivalidazione del miglior candidato richiedono la valutazione dell'AST precompilato in tempo $O(E)$ e, se il candidato cambia stato o priorità, operazioni di aggiornamento della coda in $O(\log C)$. Non vi è parsing testuale durante la ricerca; il codice corrente ricostruisce però una piccola `std::unordered_map` locale per l'ambiente `var_env` durante la valutazione del candidato, quindi non è corretto affermare che l'hot path sia completamente privo di allocazioni heap. Poiche' `compute_candidate_entry` viene invocata anche da `decide` per rivalidare la testa della coda, queste allocazioni possono cadere direttamente nel percorso piu' frequente della ricerca. Uno sviluppo futuro naturale è rendere l'hot path a zero allocazioni sostituendo `var_env` con un buffer flat preallocato: durante `init` si potrebbe assegnare a ogni variabile locale un indice statico per ciascun template/candidato e valutare gli AST leggendo un `std::vector<int>` o una piccola struttura contigua già dimensionata. In questo modo si eliminerebbero bucket e traffico heap della mappa hash durante `compute_candidate_entry`, mantenendo invariata la semantica.

Complessita' di propagate:
- per ciascun trigger attivato: aggiornamento stato body in O(1);
- aggiornamento aggregati incrementali sum/count in O(1) per singola chiamata di aggiornamento, quindi O(A) sul totale degli aggiornamenti attivati dal literal;
- per min/max con multiset implicito: inserimento/rimozione in O(log M), dove M e' il numero di valori distinti correnti nell'aggregato;
- costo complessivo su un passo di propagazione: O(A) (sum/count) oppure O(A * log M) nel caso peggiore dominato da min/max.

Complessita' di undo (backjump):
- ripristino incrementale sum/count: O(U);
- ripristino min/max con multiset implicito: O(U * log M);
- rimozione istanze lazy non piu' attive: O(U) rispetto ai trigger toccati.

In sintesi, il contributo del propagatore rimane lineare nel numero di eventi effettivamente attivati dall'assegnamento parziale, evitando il costo combinatorio a monte dovuto al grounding esaustivo delle euristiche aggregate.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 18) Confronto con letteratura e sistemi concorrenti
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Motivazione della modifica interna a Clasp:
- le API esterne standard consentono euristiche efficaci solo quando i valori necessari sono gia' disponibili in forma ground, ma non forniscono un canale equivalente per compilare e valutare espressioni aggregate dinamiche all'interno dell'hot path decisionale senza esplodere il grounding;
- il requisito di calcolo "on partial assignment" per peso/priorita' richiede accesso diretto allo stato incrementale del solver e sincronizzazione stretta con propagate/undo, ottenibile in modo robusto intervenendo nel core.

Confronto critico da esplicitare nel capitolo stato dell'arte:
1) WASP: discutere limiti del modello di integrazione euristica rispetto al calcolo dinamico di aggregati dipendenti dall'assegnamento parziale.
2) Alpha e approcci di lazy grounding nativi: evidenziare differenza di livello (grounding complessivo del programma vs lazy grounding mirato alle sole direttive euristiche), vantaggi e limiti di ciascuna scelta.
3) Contributo originale della tesi: introduzione di una pipeline ibrida in cui la semantica euristica viene "compilata" in template statici e poi valutata incrementalmente nel solver CDNL, preservando correttezza e scalabilita'.

Il posizionamento rispetto a WASP e Alpha e' quindi volutamente intermedio: l'obiettivo non e' sostituire il grounding lazy dell'intero programma, ma ottenere parte dei suoi benefici nell'hot path delle euristiche decisionali, mantenendo intatta la potenza del CDNL nativo di Clasp per il resto dell'encoding.

Questa sezione deve includere anche una discussione dei limiti attuali: copertura parziale degli aggregati supportati, costo logaritmico per min/max, e necessita' di ulteriore validazione cross-domain.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 20) I quattro approcci BSP usati nei benchmark
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Nel benchmark BSP ora conviene distinguere quattro famiglie concettuali.

1) Standard Clingo ground-and-solve (`gc`, file `test_folder/encodings/BSP/BSP_gc.lp`).
Usa direttamente le direttive native:

#heuristic b(X): x(X), not c(X), S = #sum{Y : c(Y)}. [X@S,true]
#heuristic c(X): x(X), not b(X), S = #sum{Y : b(Y)}. [X@S,true]

Qui Gringo deve produrre euristiche ground native. Il vantaggio è che questa è la semantica standard di Clingo; Lo svantaggio è il grounding bottleneck quando peso o priorità dipendono da aggregati.

2) Alpha semantics ground-and-solve (`ga`, file `test_folder/encodings/BSP/BSP_ga.lp`).
Questa variante nasce per rispondere a una domanda sperimentale precisa: quanto si riesce ad avvicinare la semantica dinamica di Alpha restando dentro il ground-and-solve standard di Clingo, cioè senza propagatore custom? L'encoding usa una simulazione a soglie. Prima calcola il massimo valore possibile della somma:

#const tot = (n*(n+1))/2.

poi introduce tutti i possibili livelli di priorità:

sum_value(0..tot).
#heuristic b(X): x(X), sum_value(S), S <= #sum{Y : c(Y)}. [X@S,true]
#heuristic c(X): x(X), sum_value(S), S <= #sum{Y : b(Y)}. [X@S,true]

L'idea è: in Alpha, durante la ricerca, l'euristica può chiedere la somma corrente degli atomi già veri. Se al momento sono veri `c(1)` e `c(3)`, la somma corrente di `c` vale 4, quindi la direttiva concettuale per `b(X)` dovrebbe avere priorità 4. Clingo nativo non può assegnare a una direttiva una priorità che cambia nel tempo, ma può avere molte direttive statiche con priorità diverse. Per questo `sum_value(S)` crea una copia della direttiva per ogni possibile `S`.

La condizione:

S <= #sum{Y : c(Y)}

è monotona nel BSP, perché tutti i pesi `Y` sono positivi. Se la somma corrente degli atomi `c(Y)` veri è `T`, allora tutte le soglie `S <= T` diventano vere, mentre le soglie `S > T` non sono ancora giustificate. Il motore Domain di Clingo, tra più direttive applicabili allo stesso target, privilegia la priorità massima. Quindi, anche se l'encoding produce molte direttive statiche, il comportamento osservato tende a selezionare la soglia più alta già soddisfatta, cioè proprio `T`.

Esempio con `n=3`, quindi `tot=6`.

Se non è vero nessun atomo `c(Y)`, la somma corrente è 0:

- è applicabile la soglia `S=0`;
- non sono applicabili le soglie `S=1..6`;
- la migliore priorità per scegliere `b(X)` è 0.

Se in seguito diventano veri `c(1)` e `c(3)`, la somma corrente è 4:

- sono applicabili le soglie `S=0,1,2,3,4`;
- non sono applicabili `S=5,6`;
- tra le direttive applicabili, quella con priorità massima è `[X@4,true]`.

In questo modo l'encoding `ga` emula, solo per somme positive e monotone come nel BSP, una priorità dinamica pari alla somma corrente.

C'è poi un secondo aspetto: il body negativo. La forma Alpha lazy originale:

#heuristic b(X): x(X), not c(X), S = #sum{Y : c(Y)}. [X@S,true]

interpreta `not c(X)` in modo ottimistico rispetto all'assegnamento parziale: l'euristica può suggerire `b(X)` finché `c(X)` non è vero. Se scrivessimo lo stesso `not c(X)` nella direttiva Clingo ground-and-solve, otterremmo una condizione più prudente: il body negativo sarebbe soddisfatto solo quando `c(X)` è già falso, non semplicemente libero. Per avvicinare il comportamento Alpha, `BSP_ga.lp` omette `not c(X)` e lascia che sia il target stesso a filtrare le decisioni inutili: se `c(X)` diventa vero, a causa del guessing mutuamente esclusivo `b(X)` non è più un target libero e la direttiva su `b(X)` non può più produrre una decisione effettiva. Finché `c(X)` è libero, invece, l'euristica rimane disponibile, come in Alpha.

Questa è però un'emulazione costosa. Una singola euristica concettuale diventa:

numero_target * numero_soglie

direttive ground. Nel BSP, `numero_target = n` e `numero_soglie = tot + 1`, dove `tot = n(n+1)/2`; per due euristiche si ottiene quindi circa:

2 * n * (n(n+1)/2 + 1)

direttive, cioè crescita cubica solo per questa parte euristica. Inoltre ogni soglia porta con sé una condizione aggregata che il solver deve rappresentare e propagare. La simulazione è utile come baseline perché mostra cosa succede quando si prova a ottenere una priorità runtime usando esclusivamente strutture ground statiche: la semantica è avvicinabile in casi monotoni, ma il prezzo è spostato sul grounding e sulla gestione di una grande famiglia di direttive.

Questo limite diventa ancora più evidente fuori dal BSP. Se l'euristica usa più aggregati, filtri multi-argomento, `#min`, `#max`, espressioni aritmetiche composte o condizioni non monotone, la codifica a soglie diventa rapidamente ingombrante o non fedele. Il propagatore lazy nasce proprio per evitare questa precompilazione: conserva un template compatto e aggiorna il valore numerico dell'euristica direttamente nel ciclo `propagate/undo/decide`.

3) Alpha semantics lazy (`la`, file `test_folder/encodings/BSP/BSP_la.lp`).
Le euristiche sono template statici:

__heuristic(__target(b),x,__n_c,__bind(s,__sum(c,0)),__weight(self),__priority(s),true).
__heuristic(__target(c),x,__n_b,__bind(s,__sum(b,0)),__weight(self),__priority(s),true).

Il propagatore valuta tutto durante il solving. In semantica Alpha, `not c(X)` significa "c(X) non e' vero": quindi l'euristica puo' attivarsi anche se c(X) è ancora libero. Gli aggregati sono incrementali: sommano/contano gli atomi attualmente veri e non aspettano che tutti gli atomi del dominio siano decisi.

4) Clingo semantics lazy (`lc`, file `test_folder/encodings/BSP/BSP_lc.lp`).
È identica alla variante lazy, ma aggiunge:

__semantics(clingo)

Questa modalita' serve a confrontare il propagatore lazy con la semantica piu' prudente di Clingo. In particolare:
- `not a(X)` e' soddisfatto solo quando `a(X)` e' assegnato esplicitamente a falso, non quando e' semplicemente libero;
- un binding aggregato come `S = #sum{Y : a(Y)}` viene usato solo quando tutti gli atomi sorgente rilevanti `a(Y)` sono assegnati, veri o falsi.

Il secondo controllo si puo' implementare come un conteggio interno degli atomi non liberi: il valore dell'aggregato viene letto solo quando `assigned_sources == total_sources`. Non e' un `#count` del programma ASP, ma un controllo runtime sullo stato dell'assegnamento del solver.

Le varianti `gc_aux` e `la_aux` non sono una quinta semantica: sono riscritture tecniche con predicati ausiliari. Servono a misurare quanto cambia il grounding quando il corpo complesso dell'euristica viene materializzato in un predicato intermedio.
