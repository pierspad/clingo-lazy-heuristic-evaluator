
# Link to the pup instances and encodings
https://github.com/tilmanni/Alpha/tree/domspec_heuristics_extended_prolog/Evaluation/PUP


per generare i grafici escludendo alcuni risultati

python gen_graphs.py --bsp-exclude BSP_la_aux.lp,BSP_gc.lp

// ======
// NOTE --------
// Questo comando e' outdated dopo la riorganizzazione della cartella.
// Ora il tool sta in test_folder/tools/gen_graphs.py, legge di default da
// test_folder/results e scrive in test_folder/results/graphs.
// L'opzione corretta e' --exclude, per esempio:
//
// python3 test_folder/tools/gen_graphs.py --exclude BSP_la_aux.lp,BSP_gc.lp
//
// END NOTE ---------
// ======

Esempio

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 1) Introduzione al problema del grounding bottleneck con euristiche e aggregati
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Answer Set Programming (ASP) è un framework di rappresentazione della conoscenza e ragionamento dichiarativo basato sulla logica del primo ordine. Il paradigma di calcolo dei moderni sistemi ASP, come Clingo, si articola in due fasi principali. Inizialmente, il grounder (Gringo) trasforma le descrizioni del primo ordine in logica proposizionale, costruendo l'universo di Herbrand ed eliminando le variabili. Successivamente, il programma proposizionale equivalente viene risolto dal solver (Clasp), il quale opera sullo spazio di ricerca tramite tecniche avanzate come il CDNL (Conflict-Driven Clause Learning) per generare le soluzioni .

Un problema critico di questo processo è che istanze di grandi dimensioni non possono essere groundate in tempi e spazi di memoria accettabili. Questa esplosione combinatoria, nota come grounding bottleneck, si può notare persino quando si utilizzano euristiche domain-specific che incorporano aggregati.  

In Clingo, i pesi e le priorità ([W@P]) di un'euristica devono essere risolti dal grounder come costanti intere statiche prima che il solving inizi. Se W o P dipendono dal risultato di un aggregato (come S), Gringo non ha un valore costante da inserire nell'istruzione per il solver. Di conseguenza, l'unico modo per preservare la logica è istanziare una direttiva euristica separata per ogni singolo valore intero che l'aggregato può generare.
L'euristica che viene aggiunta con lo scopo di velocizzare il tempo di solving finisce per saturare la RAM e rendere il processo di grounding impraticabile o il processo di solving inefficiente a causa dell'enorme spazio di ricerca generato.

Nel balanced sum problem, come definito nel paper di Comploi-Taupe, l'obiettivo è che la differenza in valore assoluto della somma degli elementi contenuti in due insiemi sia uguale a 1.
// ======
// NOTE --------
// Qui conviene essere piu' precisi: negli encoding presenti in questa repo il
// vincolo implementato e' |Sum(b)-Sum(c)| <= 1, non strettamente "uguale a 1".
// Per totali dispari le due formulazioni coincidono sul bilanciamento ottimo;
// per una descrizione generale del BSP, pero', "al massimo 1" evita ambiguita'.
// END NOTE ---------
// ======
Immaginando di dover distribuire equamente i numeri da 1 a 3 tra due insiemi, b e c, con la condizione che ogni numero può essere assegnato solo a uno dei due insiemi. Per indirizzare il solver, è utile massimizzare l'assegnazione a un insieme valutando dinamicamente la somma dell'altro. Usando la sintassi nativa, scriveremmo:

#heuristic b(X): x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]
#heuristic c(X): x(X), not b(X), S = #sum{Y : b(Y)}. [X@S, true]

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


Per rendere quindi il processo più efficiente l'obiettivo è far si che l'euristica venga valutata e groundata da gringo come un fatto semplice, delegando ad un propagatore in c++ a runtime la valutazione e il calcolo dell'euristica.

Per realizzare ciò il programma viene passato a Clingo, ma invece di far groundare a Gringo le euristiche secondo il pattern classico #heuristic, esse vengono tradotte in un fatto proposizionale (aiutandosi anche con il file asp_heuristic_converter.py), queste vengono codificate come template strutturali, ovvero fatti proposizionali statici della forma:
// ======
// NOTE --------
// Path aggiornato: il converter ora si trova in test_folder/tools/asp_heuristic_converter.py.
// Inoltre il parser legacy regex e' stato rimosso: la conversione passa solo da
// clingo.ast. Se una direttiva #heuristic non e' parseabile via AST, il converter
// fallisce esplicitamente invece di tentare un fallback testuale.
// END NOTE ---------
// ======

__heuristic(__target(TargetPred), ...argomenti flessibili...).

Il predicato target viene dichiarato esplicitamente con __target(TargetPred). 
L'ordine degli argomenti non è rilevante e vengono classificati automaticamente dal parser C++:
  - __target(pred)                             → predicato target
  - atomo semplice (es. x)                    → body positivo
  - prefisso __n_ (es. __n_c)                → body negativo (not c(X))
  - __bind(var, __agg(pred, idx?, filters...)) → binding variabile → aggregato
  - __weight(expr)                             → espressione per il peso
  - __priority(expr)                           → espressione per la priorità
  - "true" / "false" / "sign"                  → segno dell'euristica

Le espressioni (expr) supportate sono:
  - numero intero                              → costante (es. 5)
  - self                                       → valore del dominio MVP: primo argomento numerico del target (es. X in b(X))
  - variabile (nome da __bind)                 → valore corrente dell'aggregato legato
  - __add(a, b)                                → somma di due espressioni
  - __sub(a, b)                                → sottrazione
  - __mul(a, b)                                → moltiplicazione

Questo fa sì che Gringo includa nel programma proposizionale una singola riga per ogni template euristico, senza espandere le variabili di dominio, generando quindi invece soltanto:

__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).
__heuristic(__target(c), x, __n_b, __bind(s, __sum(b)), __weight(self), __priority(s), true).

Nota di perimetro MVP: `self` non e' stato eliminato nel propagatore corrente.
E' supportato dentro `__weight(...)` e `__priority(...)`, anche in espressioni
aritmetiche, ma con una semantica volutamente stretta: coincide con il primo
argomento numerico della tupla target. Quindi copre direttamente casi come
`b(X)` e `c(X)` nel BSP, dove `[X@S]` diventa `__weight(self)`,
ma non introduce ancora nomi separati per tutti gli argomenti di un target
multi-argomento. Per PUP gli altri valori contestuali vanno espressi tramite
`__bind(...)` e filtri `__filter(...)`.



I fatti generati vengono successivamente interpretati dinamicamente dal propagatore custom durante la fase di solving in Clasp. 
Il propagatore monitora l'assegnazione parziale corrente e istanzia l'euristica (calcolandone peso e priorità) in tempo reale, unicamente quando i letterali trigger nel corpo diventano veri. 
// ======
// NOTE --------
// Aggiornamento implementativo: le strutture C++ non conservano piu' i nomi
// logici principali come std::string. Target, predicati di body, variabili di
// binding e chiavi aggregate usano Clingo::Symbol, sfruttando l'identita'
// internata di Clingo. Rimangono stringhe solo per messaggi/parse helper o per
// confrontare nomi sintattici come "__sum" durante il parsing.
// END NOTE ---------
// ======


alcuni esempi:


% 1. Caso base con costanti fisse per peso e priorità
#heuristic b(X) : x(X). [1@2, true]                  
% --------------
__heuristic(__target(b), x, __weight(1), __priority(2), true).

% 2. Caso con peso = valore del dominio (self)
#heuristic b(X) : x(X), not c(X). [X@1, sign]
% --------------
__heuristic(__target(b), x, __n_c, __weight(self), __priority(1), sign).

% 3. Caso con letterali multipli nel corpo
#heuristic c(X) : a(X), b(X), not d(X). [5@2, false]
% --------------
__heuristic(__target(c), a, b, __n_d, __weight(5), __priority(2), false).

% 4. Caso con Aggregato Dinamico (priorità da aggregato)
#heuristic b(X) : x(X), not c(X). [X@S, true] % dove S è la somma corrente di c
% --------------
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).

% 5. L'ordine degli argomenti è irrilevante:
__heuristic(__target(b), __n_c, x, __bind(s, __sum(c)), __priority(s), __weight(self), true).
% è equivalente a:
__heuristic(x, __priority(s), true, __target(b), __bind(s, __sum(c)), __n_c, __weight(self)).

% 6. Caso con peso e priorità ENTRAMBI da aggregati diversi
#heuristic b(X) : x(X), not c(X). [S1@S2, true] % S1=count(c), S2=sum(c)
% --------------
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)), __bind(k, __count(c)), __weight(k), __priority(s), true).

% 7. NOVITÀ: Espressioni matematiche complesse
% Weight = S + 1, Priority = S * 10
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)), __weight(__add(s, 1)), __priority(__mul(s, 10)), true).

% 8. Combinazione di self con aggregato
% Weight = self + somma_di_c, Priority = somma_di_c
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)), __weight(__add(self, s)), __priority(s), true).

% 9. Stessa variabile usata sia in weight che in priority
% Weight = S, Priority = S + 1
__heuristic(__target(b), x, __n_c, __bind(s, __sum(c)), __weight(s), __priority(__add(s, 1)), true).



%% ------------------------------------------------------

Di solito il funzionamento di un propagatore (nello specifico della classe
CLingo::Heuristic che eredita da Clingo::Propagator) si articola nelle fasi
seguenti:

1) Prima di fare qualunque cosa c'e' il metodo init. In init il propagatore
euristico analizza i fatti ground, costruisce le strutture dati interne e
registra, tramite add_watch, i letterali solver di cui vuole osservare i
cambiamenti di stato. Il watch non viene registrato su un fatto astratto, ma
sul literal solver corrispondente alla condizione che interessa il
propagatore. Se un'euristica dipende dal fatto che c(X) sia falso, cioe' da
`not c(X)` nel body, il propagatore deve registrare il watch sul literal solver
negativo corrispondente a c(X), cosi' da essere notificato quando quella
condizione diventa vera nell'assegnamento corrente.

2) Segue la fase di unit propagation, piu' precisamente Boolean Constraint
Propagation (BCP). Il solver applica la propagazione booleana sui vincoli e
sulle nogood gia' presenti. Durante questa fase, ogni volta che un letterale
osservato tramite watch cambia stato in modo rilevante, il solver invoca il
metodo propagate del propagatore su quel letterale.

In generale un propagatore puo' aggiungere nuove nogood tramite add_clause()
quando rileva un'inconsistenza. Nel caso specifico dello HeuristicPropagator,
pero', la funzione primaria di propagate non e' produrre nuova deduzione
logica: e' aggiornare incrementalmente le strutture dati interne, in
particolare gli AggregateState, e mantenere coerente la lista dei trigger
euristici attivi rispetto all'assegnamento parziale corrente.

Questo ciclo si ripete fino a quando non si raggiunge un fixpoint, ovvero un
punto in cui ne' la BCP ne' i propagatori registrati producono ulteriori
aggiornamenti.

3) raggiunto il fixpoint il solver è costretto a esplorare una diramazione dell'albero di ricerca e qui chiama il metodo decide.

il metodo decide sceglie un letterale (che può essere di segno positivo o negativo) da far diventare vero nel ramo corrente e il ciclo si ripete dal punto 2.
fino a quando non si è dimostrato che non si possono trovare più nuovi AS

4) Raggiunto un assegnamento totale, o un fixpoint intermedio a seconda della configurazione, il solver invoca il metodo check. In questa fase il propagatore effettua una validazione globale sul modello candidato, potendo generare "lazy no-good" per scartare soluzioni che soddisfano le regole ASP ma violano logiche complesse del dominio esterno valutabili solo a modello completo.
// ======
// NOTE --------
// Questa frase descrive correttamente il ruolo generale di Propagator::check,
// ma il nostro HeuristicPropagator corrente non override-a check e non aggiunge
// nogood lazy. In questo MVP usa init/propagate/undo/decide per mantenere e
// leggere stati euristici; la validazione dei modelli resta nell'encoding ASP
// o negli script di validazione esterni.
// END NOTE ---------
// ======

5) Passaggio "extra": se durante la propagazione il solver falsifica una
nogood, viene rilevato un conflitto. Il conflitto viene analizzato per
costruire una nogood appresa e determinare il livello di backjumping, spesso
rispetto al first unique implication point.

Il metodo undo non viene chiamato solo in presenza di un conflitto, ma in
generale durante il backtracking, incluso il backjumping guidato dai conflitti.
Clasp gli passa i letterali che stanno per essere de-assegnati, permettendo al
propagatore euristico di disfare le modifiche di stato esattamente nell'ordine
inverso rispetto a propagate e di riportare AggregateState e trigger attivi
allo stato coerente con il nuovo assegnamento parziale.



%% ------------------------------------------------------

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 10) Ottimizzazione vincolo in vincolo lineare BSP
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Il vincolo 

:- not min_val <= #sum{ Y : b(Y) } <= max_val.

rappresenta un'ottimizzazione matematica applicata al Balanced Sum Problem (BSP). 
Nel problema originale, l'obiettivo e' suddividere i numeri da 1 a n in due insiemi disgiunti, b e c, in modo tale che la differenza in valore assoluto tra la somma dei loro elementi sia al massimo 1.

Dimostrazione formale del check.

Sia tot la somma totale dei numeri da 1 a n, calcolabile tramite la formula di
Gauss:
$$tot = \frac{n(n+1)}{2}$$

Poiche' il costrutto di scelta `1 { b(X); c(X) } 1 :- x(X).` impone che ogni
numero appartenga esattamente a uno dei due insiemi, vale necessariamente:
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

Questi due estremi corrispondono matematicamente alle costanti min_val e
max_val definite in testa al programma. L'aggregato `#sum{ Y : b(Y) }`
calcola la somma degli elementi assegnati a b; il vincolo di integrita'
scarta tutti i modelli in cui tale somma non ricade nell'intervallo valido.

Questa forma chiusa permette al grounder di precalcolare i bound statici,
convertendo il controllo non lineare commentato `(SB-SC)**2 > 1` in un
semplice weight constraint lineare. In questo modo Clasp deve tracciare un
solo aggregato con due estremi costanti, invece di esplorare combinazioni di
somme e differenze quadratiche; il risultato e' una riduzione drastica del
numero di conflitti generati durante la ricerca.




% output di 
% gringo --text BSP/BSP_gc.lp BSP_instances/BSP_range.lp
// ======
// NOTE --------
// Path outdated: dopo il refactor del layout il comando equivalente e':
// clingo --text test_folder/encodings/BSP/BSP_gc.lp test_folder/instances/BSP_instances/BSP_range.lp
// Lo stesso vale per gli altri esempi BSP sotto: gli encoding stanno in
// encodings/BSP/ e le istanze in instances/BSP_instances/.
// END NOTE ---------
// ======

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
% gringo --text BSP/BSP_la_co.lp BSP_instances/BSP_range.lp
// ======
// NOTE --------
// Anche qui i path corretti sono:
// test_folder/encodings/BSP/BSP_la_co.lp
// test_folder/instances/BSP_instances/BSP_range.lp
// END NOTE ---------
// ======

__heuristic(__target(b),x,__n_c,__bind(s,__sum(c)),__weight(self),__priority(s),true).
__heuristic(__target(c),x,__n_b,__bind(s,__sum(b)),__weight(self),__priority(s),true).
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
% 15) Definizione formale della sintassi (__heuristic/N)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Per rendere la specifica rigorosa, la sintassi accettata dal costrutto
__heuristic/N puo' essere formalizzata in EBNF come segue.

<heuristic-fact>   ::= "__heuristic(" <h-arg> {"," <h-arg>} ")."

<target>           ::= "__target(" <pred-id> ")"

<h-arg>            ::= <target>
              | <pos-lit>
              | <neg-lit>
              | <bind>
              | <weight>
              | <priority>
              | <sign>

<pos-lit>          ::= <pred-id>
<neg-lit>          ::= "__n_" <pred-id>

<bind>             ::= "__bind(" <var-id> "," <agg-expr> ")"
<agg-expr>         ::= "__sum(" <pred-id> ["," <arg-index>] {"," <filter>} ")"
              | "__count(" <pred-id> ["," <arg-index>] {"," <filter>} ")"
              | "__min(" <pred-id> ["," <arg-index>] {"," <filter>} ")"
              | "__max(" <pred-id> ["," <arg-index>] {"," <filter>} ")"
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

<pred-id>          ::= identificatore predicato ASP valido
<var-id>           ::= identificatore variabile locale valida
<arg-index>        ::= indice numerico 0-based dell'argomento aggregato
<source-index>     ::= indice numerico 0-based dell'argomento del predicato aggregato
<target-index>     ::= indice numerico 0-based dell'argomento del target
<offset>           ::= intero con segno applicato al valore target
<int>              ::= intero con segno in base 10

Vincoli semantici addizionali:
1) deve essere presente esattamente un argomento <target>;
2) ogni <var-id> usata in <arith-expr> deve essere introdotta da almeno un
  __bind nello stesso fatto __heuristic/N;
// ======
// NOTE --------
// Questa regola e' incompleta per la versione corrente: una variabile locale puo'
// essere introdotta anche da __bind_arg(var, source_idx) dentro un __body(...)
// esplicito. Il parser C++ accetta quindi sia variabili da aggregato (__bind)
// sia variabili estratte da un predicato di body (__bind_arg).
// END NOTE ---------
// ======
3) la semantica MVP di "self" coincide con il primo argomento numerico
  dell'atomo target nell'istanza corrente; in presenza di tuple target
  multi-argomento, "self" valuta specificamente il primo argomento numerico
  della tupla, conformemente al comportamento implementato nel parser C++;
4) l'ordine degli argomenti e' irrilevante;
5) in presenza di bind multipli sullo stesso <var-id> si applica il vincolo di
  unicita' (errore di parsing/inizializzazione).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 16) Analisi di complessita' temporale e spaziale
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Si introducono le seguenti grandezze:
- T = numero di template __heuristic/N nel programma ground;
- B = numero medio di letterali di body monitorati per template;
- K = numero medio di bind/aggregati per template;
- E = dimensione media (nodi) degli AST di weight/priority;
- A = numero di aggiornamenti aggregato attivati da un literal in propagate;
- U = numero di literal annullati in un singolo undo.
// ======
// NOTE --------
// Mancano due grandezze utili per descrivere il codice attuale:
// - C = numero di CandidateState materializzati in init, cioe' target ground
//   compatibili con body/trigger;
// - S = numero di atomi sorgente osservati per gli aggregati runtime.
// T da solo descrive i template, ma non il volume runtime: il costo reale di
// init dipende anche dalla scansione degli atomi simbolici e dalla costruzione
// dei CandidateState. Inoltre AtomKey e RuntimeAggregateKey usano ancora tuple
// di interi (std::vector<int>) per il matching multi-argomento: e' semplice e
// leggibile, ma resta un hotspot da profilare prima di sostituirlo con chiavi
// piu' compatte basate su literal_t.
// END NOTE ---------
// ======

Tabella di confronto sintetico (per il testo tesi):

| Caratteristica | Grounding Standard | Lazy Heuristic |
| :--- | :--- | :--- |
| Dimensione programma | Esplosione combinatoria O(N^k) | O(T) template |
| Utilizzo RAM | Cresce con le istanze (fino a saturazione) | Basso e quasi costante |
| Flessibilita' euristica | Statica (valori fissati al grounding) | Dinamica (valutata su assegnamento parziale) |
| Costo decisione | Lookup su regole gia' groundate | O(E) su AST precompilato |

Confronto asintotico ad alto livello:
- Standard: il grounding delle euristiche aggregate puo' richiedere O(N^k)
  regole, dove k e' il numero di variabili nel corpo euristico.
- Lazy: il grounding resta O(T) sui template; il costo runtime e' O(E) per
  istanza attiva, con T numero template ed E dimensione AST.

Complessita' di inizializzazione (init_lazy_mode):
- tempo: O(T * (B + K + E));
- spazio: O(T * (B + K + E)) per indici, metadata e AST compilati.

Complessita' del percorso caldo (decide):
- accesso ai valori locali tramite env_buffer_ indicizzato: O(1) per variabile;
- valutazione espressioni precompilate: O(E);
- overhead totale per istanza attiva: O(E), senza parsing dinamico, allocazioni
  heap o lookup stringa.
// ======
// NOTE --------
// Questa descrizione e' outdated. L'implementazione corrente non usa env_buffer_
// indicizzato: usa mappe su Clingo::Symbol per l'ambiente delle variabili e una
// candidate_queue_ ordinata (std::set) per evitare la scansione lineare in decide.
// I lookup non sono piu' lookup su std::string, ma restano lookup hash; quindi il
// percorso caldo reale e' dominato da estrazione/rivalidazione del miglior candidato,
// valutazione AST O(E) e aggiornamenti O(log C) quando un candidato entra/esce dalla coda.
// END NOTE ---------
// ======

Complessita' di propagate:
- per ciascun trigger attivato: aggiornamento stato body in O(1);
- aggiornamento aggregati incrementali sum/count in O(1) per singola chiamata
  di aggiornamento, quindi O(A) sul totale degli aggiornamenti attivati dal
  literal;
- per min/max con multiset implicito: inserimento/rimozione in O(log M), dove
  M e' il numero di valori distinti correnti nell'aggregato;
- costo complessivo su un passo di propagazione: O(A) (sum/count) oppure
  O(A * log M) nel caso peggiore dominato da min/max.

Complessita' di undo (backjump):
- ripristino incrementale sum/count: O(U);
- ripristino min/max con multiset implicito: O(U * log M);
- rimozione istanze lazy non piu' attive: O(U) rispetto ai trigger toccati.

In sintesi, il contributo del propagatore rimane lineare nel numero di eventi
effettivamente attivati dall'assegnamento parziale, evitando il costo
combinatorio a monte dovuto al grounding esaustivo delle euristiche aggregate.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 17) Estensione benchmark su domini non sintetici (protocollo)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Per consolidare la validita' esterna, e' necessario aggiungere almeno un
benchmark su dominio reale con dipendenze causali irregolari. Protocollo
proposto:

Dataset minimo:
1) Planning: istanze Blocks/Logistics/PDDL gia' convertite in ASP.
2) Scheduling: job-shop o course timetabling con vincoli multipli.
3) Routing: VRP/TSP con capacita' e finestre temporali (almeno una famiglia).

Configurazione sperimentale:
1) stessa versione di Clingo/Clasp e stessi flag tra baseline e lazy;
2) timeout fisso (es. 600s) e limite memoria fisso (es. 8GB);
3) almeno 5 run per istanza con media e deviazione standard;
4) metriche: grounding time, solving time, totale, RSS max, conflicts,
  choices, propagations, numero regole groundate.
// ======
// NOTE --------
// Lo script benchmark corrente e' stato consolidato: benchmark_bsp.sh e
// benchmark_pup.sh sono ora iteratori sottili, mentre benchmark_runner.py esegue
// il singolo run con --outf=2 --stats=2 e parsa le metriche solver dal JSON.
// I CSV finiscono in test_folder/results/. Rimane un pass --text separato solo
// per contare righe/fatti del programma ground, perche' quei conteggi non sono
// esposti direttamente nel JSON di Clingo.
// END NOTE ---------
// ======

Obiettivo analitico:
1) verificare se il beneficio persiste oltre BSP quando la ricerca non e'
  deterministica;
2) misurare trade-off tra overhead runtime del propagatore e riduzione del
  grounding;
3) identificare classi di istanze in cui la strategia lazy e' neutra o peggiora
  (analisi di robustezza, non solo best-case).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 18) Confronto con letteratura e sistemi concorrenti
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Motivazione della modifica interna a Clasp:
- le API esterne standard consentono euristiche efficaci solo quando i valori
  necessari sono gia' disponibili in forma ground, ma non forniscono un canale
  equivalente per compilare e valutare espressioni aggregate dinamiche
  all'interno dell'hot path decisionale senza esplodere il grounding;
- il requisito di calcolo "on partial assignment" per peso/priorita' richiede
  accesso diretto allo stato incrementale del solver e sincronizzazione stretta
  con propagate/undo, ottenibile in modo robusto intervenendo nel core.

Confronto critico da esplicitare nel capitolo stato dell'arte:
1) WASP: discutere limiti del modello di integrazione euristica rispetto al
  calcolo dinamico di aggregati dipendenti dall'assegnamento parziale.
2) Alpha e approcci di lazy grounding nativi: evidenziare differenza di livello
  (grounding complessivo del programma vs lazy grounding mirato alle sole
  direttive euristiche), vantaggi e limiti di ciascuna scelta.
3) Contributo originale della tesi: introduzione di una pipeline ibrida in cui
  la semantica euristica viene "compilata" in template statici e poi valutata
  incrementalmente nel solver CDNL, preservando correttezza e scalabilita'.

Il posizionamento rispetto a WASP e Alpha e' quindi volutamente intermedio:
l'obiettivo non e' sostituire il grounding lazy dell'intero programma, ma
ottenere parte dei suoi benefici nell'hot path delle euristiche decisionali,
mantenendo intatta la potenza del CDNL nativo di Clasp per il resto
dell'encoding.

Questa sezione deve includere anche una discussione dei limiti attuali:
copertura parziale degli aggregati supportati, costo logaritmico per min/max,
e necessita' di ulteriore validazione cross-domain.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 19) Normalizzazione strutturale e Knowledge Compilation degli Encoding
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

L'integrazione delle euristiche native nel framework lazy richiede una fase preliminare di normalizzazione sintattica degli encoding originali.
Gli encoding nativi del PUP presentano spesso aggregati con corpi congiuntivi complessi e variabili logiche intermedie utilizzate per il calcolo dei pesi. 
Per garantire la compatibilità con il parser C++ e il convertitore Python, i file originali subiscono due trasformazioni architetturali rigorose.

In primo luogo, si applica l'estrazione dei corpi complessi. 
Le congiunzioni all'interno degli aggregati originali vengono isolate e appiattite in predicati ausiliari dinamici dedicati (ad esempio, definendo un dyn_deg_sensor). 
Questo garantisce che l'aggregato lazy dipenda da un singolo letterale trigger valutabile in tempo reale dal propagatore custom, soddisfacendo i requisiti di linearità sintattica del costrutto __bind.

In secondo luogo, si procede con l'inlining delle espressioni matematiche. 
Le variabili intermedie definite nel corpo dell'euristica per scomporre il calcolo di peso e priorità vengono eliminate. 
L'intera logica aritmetica viene collassata direttamente all'interno dei modificatori della direttiva finale. Questa espansione è architetturalmente obbligatoria affinché l'Abstract Syntax Tree (AST) precompilato nella fase di init_lazy_mode  possa mappare direttamente le variabili di aggregazione sull'ambiente di valutazione (environment array) . 
Ciò elimina la necessità di eseguire il parsing di dipendenze annidate a runtime o di effettuare allocazioni dinamiche sulla memoria heap. 
Queste modifiche mantengono intatta la semantica logica del problema originale e assicurano che il propagatore non introduca overhead durante la propagazione e l'undo.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 20) I quattro approcci BSP usati nei benchmark
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Nel benchmark BSP ora conviene distinguere quattro famiglie concettuali.

1) Standard Clingo ground-and-solve (`gc`, file BSP/BSP_gc.lp).
// ======
// NOTE --------
// Path aggiornato per tutta questa sezione:
// BSP/BSP_*.lp -> test_folder/encodings/BSP/BSP_*.lp
// PUP/PUP_*.lp -> test_folder/encodings/PUP/PUP_*.lp
// BSP_instances/ -> test_folder/instances/BSP_instances/
// PUP_instances/ -> test_folder/instances/PUP_instances/
// Gli script benchmark ora stanno in test_folder/benchmarks/ e usano
// benchmark_runner.py con output CSV in test_folder/results/.
// END NOTE ---------
// ======
Usa direttamente le direttive native:

#heuristic b(X): x(X), not c(X), S = #sum{Y : c(Y)}. [X@S,true]
#heuristic c(X): x(X), not b(X), S = #sum{Y : b(Y)}. [X@S,true]

Qui Gringo deve produrre euristiche ground native. Il vantaggio e' che questa
e' la semantica standard di Clingo; lo svantaggio e' il grounding bottleneck
quando peso o priorita' dipendono da aggregati.

2) Alpha semantics ground-and-solve (`ga`, file BSP/BSP_ga.lp).
Questa variante non usa il propagatore lazy. Emula l'idea Alpha con direttive
native gia' groundabili:

sum_value(0..tot).
#heuristic b(X): x(X), sum_value(S), S <= #sum{Y : c(Y)}. [X@S,true]
#heuristic c(X): x(X), sum_value(S), S <= #sum{Y : b(Y)}. [X@S,true]

La condizione `S <= #sum{...}` e' monotona rispetto agli atomi gia' veri.
Dato che in BSP i valori sono positivi, tra tutte le regole attive vince la
priorita' massima S, cioe' la somma corrente degli atomi assegnati a vero.
Questo e' utile per testing perche' resta "ground and solve", ma produce molte
euristiche ground e quindi puo' essere molto piu' pesante della variante lazy.

3) Alpha semantics lazy (`la`, file BSP/BSP_la.lp).
Le euristiche sono template statici:

__heuristic(__target(b),x,__n_c,__bind(s,__sum(c,0)),__weight(self),__priority(s),true).
__heuristic(__target(c),x,__n_b,__bind(s,__sum(b,0)),__weight(self),__priority(s),true).

Il propagatore valuta tutto durante il solving. In semantica Alpha, `not c(X)`
significa "c(X) non e' vero": quindi l'euristica puo' attivarsi anche se c(X)
e' ancora libero. Gli aggregati sono incrementali: sommano/contano gli atomi
attualmente veri e non aspettano che tutti gli atomi del dominio siano decisi.

4) Clingo semantics lazy (`lc`, file BSP/BSP_lc.lp).
E' identica alla variante lazy, ma aggiunge:

__semantics(clingo)

Questa modalita' serve a confrontare il propagatore lazy con la semantica piu'
prudente di Clingo. In particolare:
- `not a(X)` e' soddisfatto solo quando `a(X)` e' assegnato esplicitamente a
  falso, non quando e' semplicemente libero;
- un binding aggregato come `S = #sum{Y : a(Y)}` viene usato solo quando tutti
  gli atomi sorgente rilevanti `a(Y)` sono assegnati, veri o falsi.

Il secondo controllo si puo' implementare come un conteggio interno degli
atomi non liberi: il valore dell'aggregato viene letto solo quando
`assigned_sources == total_sources`. Non e' un `#count` del programma ASP, ma
un controllo runtime sullo stato dell'assegnamento del solver.

Le varianti `gc_aux` e `la_aux` non sono una quinta semantica: sono riscritture
tecniche con predicati ausiliari. Servono a misurare quanto cambia il grounding
quando il corpo complesso dell'euristica viene materializzato in un predicato
intermedio.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 21) Nota sul suggerimento del professore: __h(...)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

La forma annotata dal professore:

__h(b(x), x(x), not_a(x), s=a(y)).

va letta come notazione compatta, non necessariamente come sintassi finale del
nostro implementativo. L'idea e' rappresentare una direttiva euristica come un
fatto strutturale invece che come `#heuristic` nativa:
- `b(x)` e' il target dell'euristica;
- `x(x)` e' un trigger positivo del body;
- `not_a(x)` rappresenta il body negativo `not a(X)`;
- `s=a(y)` rappresenta il binding di una variabile locale `s` a un aggregato
  calcolato sugli atomi `a(Y)`.

Nel nostro codice la stessa idea e' espressa con la sintassi piu' esplicita:

__heuristic(__target(b), x, __n_a, __bind(s, __sum(a,0)), __weight(...), __priority(s), true).

Quindi il punto del professore non e' "dimostrare" un nuovo vincolo logico, ma
separare la descrizione dell'euristica dalla sua istanziazione. In questo modo
Gringo grounda un fatto piccolo e il propagatore decide a runtime quando
applicarlo e con quali valori di peso/priorita'.
