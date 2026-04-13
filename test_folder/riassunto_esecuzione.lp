



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

Durante decide, per ogni istanza lazy attiva viene riusato un environment flat
array preallocato (env_buffer_), dove env[0] rappresenta __self__ e gli altri
slot sono risolti tramite var_bindings pre-calcolati in init_lazy_mode.
La valutazione di weight_expr e priority_expr avviene quindi per visita
dell'albero, partendo dai nodi foglia e propagando i risultati verso i nodi
interni, senza parsing di stringhe a runtime. Inoltre, quando un'espressione
non dipende da variabili __bind (es. costante o solo self), il valore viene
pre-valutato in propagate e riusato in decide senza nuova evaluate().


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
non basta l'inversa aritmetica: MinState e MaxState mantengono un multiset
implicito (mappa valore->occorrenze) che permette di recuperare l'estremo
precedente in O(log M) senza ricalcolo totale dell'aggregato. In parallelo,
undo elimina anche le istanze lazy create dai trigger non piu' veri,
mantenendo allineate active_body_lits e lazy_targets_ con lo stato effettivo
del solver.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 12) Valutazione empirica (benchmark.sh + graphs.py)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

La validazione sperimentale e' stata condotta con benchmark.sh, confrontando la
codifica standard (#heuristic con aggregati groundati dal front-end) contro la
variante lazy con template __heuristic/N e valutazione runtime nel propagatore.
I risultati, salvati in test-results/results.csv e visualizzati da graphs.py,
coprono N=10..100 su 5 seed per punto.

Lettura sintetica dei grafici:
1) RAM: la variante standard cresce da circa 10 MB (N=10) a circa 452 MB
  (media a N=100), mentre la variante lazy resta circa costante attorno a
  10 MB anche alle istanze massime.
2) Solving Time: resta molto basso in entrambe le varianti (ordine
  sub-secondo). A N=100 il solving medio e' 0.078s (standard) contro ~0s
  (lazy), indicando che il propagatore non introduce overhead significativo
  nel core CDNL.
3) Grounding/Tempo totale: a N=100 le regole ground passano da 1,041,498
  (standard) a 806 (lazy) e il tempo totale medio da 2.3266s a 0.0020s.

Questi dati confermano che il vantaggio principale e' la rimozione del
grounding bottleneck; la fase di solving rimane invece sostanzialmente
comparabile e non penalizzata dalla valutazione lazy.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 13) Contestualizzazione dei grafici solving/conflicts/choices
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

L'osservazione sperimentale "solving time ~ 0" e "conflicts = 0" nella
modalita' lazy non va interpretata come una disattivazione del motore CDNL.
Il solver continua a operare con la stessa pipeline decisione-propagazione-
analisi-conflitto-backjump, ma in queste istanze la sequenza di decisioni
indotta dall'euristica coincide con un cammino risolutivo privo di scelte
errate. In altre parole, l'albero di ricerca non viene bypassato: viene
percorso lungo un unico ramo utile senza generare nodi di conflitto.

Il grafico "Choices" mostra infatti una crescita lineare coerente con il
numero di assegnamenti necessari per completare la soluzione BSP. L'assenza di
backtracking riduce a zero i conflitti e rende trascurabile il tempo di
solving residuo. Il miglioramento osservato e' quindi una evidenza di
euristica di dominio quasi perfetta, resa praticabile dal fatto che il
grounding non esplode piu' in memoria.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 13-bis) Derivazione formale del vincolo lineare BSP
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Il vincolo `:- not min_val <= #sum{ Y : b(Y) } <= max_val.` rappresenta
un'ottimizzazione matematica applicata al Balanced Sum Problem (BSP). Nel
problema originale, l'obiettivo e' suddividere i numeri da 1 a n in due
insiemi disgiunti, b e c, in modo tale che la differenza in valore assoluto
tra la somma dei loro elementi sia al massimo 1.

Dimostrazione formale del check.
Sia tot la somma totale dei numeri da 1 a n, calcolabile tramite la formula di
Gauss: $tot = \frac{n(n+1)}{2}$. Poiche' il costrutto di scelta
`1 { b(X); c(X) } 1 :- x(X).` impone che ogni numero appartenga esattamente a
uno dei due insiemi, vale necessariamente: $Sum(b) + Sum(c) = tot$.
Da questa equivalenza segue: $Sum(c) = tot - Sum(b)$.

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

Questa formulazione e' detta lineare in contrapposizione al controllo
commentato `(SB-SC)**2 > 1`. Il quadrato introduce una non-linearita'
aritmetica che, in ASP, costringe il grounder a istanziare variabili per
tutte le possibili combinazioni di somme e a valutarne la differenza
quadratica. La forma ottimizzata riduce invece la verifica a un singolo
aggregato lineare con due bound costanti precalcolati in grounding. Per Clasp
questo si traduce in un singolo weight constraint, con meno aggregati da
tracciare a runtime e meno operazioni aritmetiche costose, riducendo in modo
netto i conflitti durante la ricerca.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 14) Definizione formale della sintassi (__heuristic/N)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Per rendere la specifica rigorosa, la sintassi accettata dal costrutto
__heuristic/N puo' essere formalizzata in EBNF come segue.

<heuristic-fact>   ::= "__heuristic(" <target> {"," <h-arg>} ")."

<target>           ::= <pred-id>

<h-arg>            ::= <pos-lit>
              | <neg-lit>
              | <bind>
              | <weight>
              | <priority>
              | <sign>

<pos-lit>          ::= <pred-id>
<neg-lit>          ::= "__n_" <pred-id>

<bind>             ::= "__bind(" <var-id> "," <agg-expr> ")"
<agg-expr>         ::= "__sum(" <pred-id> ")"
              | "__count(" <pred-id> ")"
              | "__min(" <pred-id> ")"
              | "__max(" <pred-id> ")"

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
<int>              ::= intero con segno in base 10

Vincoli semantici addizionali:
1) il primo argomento deve essere sempre <target>;
2) ogni <var-id> usata in <arith-expr> deve essere introdotta da almeno un
  __bind nello stesso fatto __heuristic/N;
3) la semantica di "self" coincide con il valore di dominio dell'atomo target
  nell'istanza corrente;
4) l'ordine degli argomenti dopo il primo e' irrilevante;
5) in presenza di bind multipli sullo stesso <var-id> si applica il vincolo di
  unicita' (errore di parsing/inizializzazione).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 15) Analisi di complessita' temporale e spaziale
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Si introducono le seguenti grandezze:
- T = numero di template __heuristic/N nel programma ground;
- B = numero medio di letterali di body monitorati per template;
- K = numero medio di bind/aggregati per template;
- E = dimensione media (nodi) degli AST di weight/priority;
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

Complessita' di propagate:
- per ciascun trigger attivato: aggiornamento stato body in O(1);
- aggiornamento aggregati incrementali sum/count in O(A);
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
% 16) Estensione benchmark su domini non sintetici (protocollo)
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

Obiettivo analitico:
1) verificare se il beneficio persiste oltre BSP quando la ricerca non e'
  deterministica;
2) misurare trade-off tra overhead runtime del propagatore e riduzione del
  grounding;
3) identificare classi di istanze in cui la strategia lazy e' neutra o peggiora
  (analisi di robustezza, non solo best-case).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 17) Confronto con letteratura e sistemi concorrenti
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

Questa sezione deve includere anche una discussione dei limiti attuali:
copertura parziale degli aggregati supportati, costo logaritmico per min/max,
e necessita' di ulteriore validazione cross-domain.