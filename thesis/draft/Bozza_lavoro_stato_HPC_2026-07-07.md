# Bozza di lavoro — Punto della situazione (7 luglio 2026)

## Lazy heuristics in clingo: tesi + smoke test HPC (PUP/HRP)

> **Nota di lettura.** Questo documento **non è la tesi da consegnare**. È una bozza di lavoro con la stessa scaletta della tesi ufficiale (`thesis/Tesi_Lazy_Heuristics/`), che uso per fare il punto prima di aggiornare i capitoli LaTeX veri. Dove un grafico o un dato non torna, lo scrivo esplicitamente ("qui il grafico dice X, dovrebbe dire Y, va sistemato Z") invece di nasconderlo o interpretarlo generosamente. La tesi ufficiale in inglese non viene toccata da questo documento.

---

## 0. Executive summary

1. Il capitolo Risultati della tesi ufficiale è **completo e solido solo per BSP** (campagna locale, n=10..120). PUP e HRP erano "cablati ma in attesa dei numeri definitivi" — così li descrive sia la tesi (§3.7) sia l'audit del 2 luglio.
2. Ho analizzato in dettaglio le cartelle di grafici appena generate in `test_folder/clingo_hpc_graphs/` (`graphs-native`, `graphs-prolog`, `graphs-comparison-native-prolog`, per BSP/PUP/HRP).
3. **Scoperta principale di questa sessione, e la più importante da tenere a mente**: questi grafici **non sono la campagna HPC completa**. Sono, con altissima confidenza, l'output dello **smoke test** (`3_run_benchmark_short_hpc.sh`), non della suite completa (`4_run_benchmark_hpc.sh`). Le prove sono al punto 4.2 qui sotto: combaciano esattamente i parametri (`TIMEOUT=15`, BSP n=3..5, 2 istanze per PUP e per HRP).
4. Conseguenza diretta: **quasi nessuno di questi grafici è utilizzabile per scrivere risultati definitivi in tesi**. Le taglie sono troppo piccole per dire alcunché su asintotica, memoria, crossover lazy/ground: è esattamente il test pensato per "verificare che la sottomissione SLURM funzioni", non per misurare.
5. Ho comunque trovato un paio di segnali interessanti (in particolare su PUP, dove anche a N=20/40 la variante `lc` nativa mostra un comportamento anomalo) che vale la pena tenere d'occhio nella full run — ma **da NON scrivere in tesi finché non confermati** su dati veri.
6. Ho trovato inoltre bug riproducibili nella pipeline di grafici (tabella "verdetto" vuota, assi con doppio zero, serie mancanti per il backend Prolog lazy) elencati al §5.6, con relativa checklist da sistemare prima del prossimo run.

---

## 1. Introduzione (richiamo)

Il progetto estende clingo con un **propagatore di euristiche lazy**: invece di espandere le direttive `#heuristic` a grounding-time (approccio *ground-and-solve*, prefisso `g`), le euristiche restano in forma compatta (pochi fatti) e vengono valutate a runtime a ogni punto di decisione (approccio *lazy*, prefisso `l`). Il secondo asse ortogonale è la **semantica di lettura dello stato parziale**: *clingo-like* (`c`, negazione e aggregati su valori stabiliti) vs *Alpha-like* (`a`, negazione e aggregati sullo stato parziale corrente, cioè euristiche genuinamente dinamiche). Incrociando i due assi si ottengono le quattro varianti `gc/ga/lc/la` più il baseline `gc_noheur`, su tre problemi (BSP, PUP, HRP) e due backend di valutazione lazy (native C++, Prolog/SWI in-process). Per i dettagli concettuali rimando alla Sezione 1 della tesi ufficiale (`1 - Introduzione.tex`), che resta valida e non necessita modifiche a questo giro.

---

## 2. Metodologia (richiamo + stato del codice)

Il framework a due assi, la regola di *flattening* peso/priorità (`W_flat = W + P·M`), l'architettura dei due backend e gli encoding di BSP/PUP/HRP sono descritti in `2 - Metodologia.tex` e restano l'architettura di riferimento. Due cose da tenere a mente per l'interpretazione dei grafici di questa sessione:

- **Bug di semantica corretto il 2 luglio** (`docs/AUDIT-2026-07-02.md`, §1): le varianti native `lc` di PUP e HRP usavano priorità non appiattite, contando su un ranking globale (priority, weight) che il backend nativo in semantica clingo *non* applica (in clingo la priorità arbitra solo modifiche sullo stesso target). Risultato: ordine di decisione invertito (sensori prima delle zone in PUP, riempimento cabinet prima del riuso in HRP). Il fix è applicato negli encoding (`PUP_lc.lp`, `HRP_lc.lp` nativi). **Qualsiasi dato precedente al 2 luglio per `lc` nativo su PUP/HRP è da considerare invalido**; i grafici che analizzo qui sotto sono successivi al fix (i file sono datati 7 luglio), quindi dovrebbero incorporarlo — ma è un punto da verificare esplicitamente e non dare per scontato.
- Il caveat di misura della tesi (§2.8): la memoria è RSS di picco dell'intero processo, end-to-end, e include per i lazy-Prolog il motore SWI in-process con overhead fisso indipendente da n. Su istanze piccolissime (come quelle di questo smoke test) questo overhead fisso **domina** qualunque differenza strutturale — un altro motivo per cui questi numeri non sono ancora significativi.

---

## 3. Stato dei dati sperimentali disponibili

### 3.1 BSP — campagna completa (invariata)

La Sezione 3 della tesi (`3 - Risultati.tex`) riporta la campagna locale completa su BSP, n=10..120: crescita Θ(n³) delle direttive ground (confermata dalla formula esatta, 1.010.200 direttive a n=100 per `gc`), 2 fatti lazy costanti, `la` come strategia greedy perfetta (100 scelte, 0 conflitti a n=100), `lc` vicino al baseline, RSS che conferma il risparmio a n grandi. Questo materiale è solido e **non va toccato** sulla base dei grafici HPC appena arrivati: sono due dataset diversi, a scale diverse, e non sono comparabili punto a punto (istanze diverse, macchina diversa — locale vs cluster SLURM).

### 3.2 Il nuovo run HPC: di cosa si tratta davvero

Questa è la parte da capire bene prima di scrivere qualunque riga di tesi. Il repository ha due script per il cluster:

| Script | Timeout | BSP | PUP | HRP | Scopo dichiarato nel file |
|---|---|---|---|---|---|
| `3_run_benchmark_short_hpc.sh` | **15 s** | n = 3..5 | 2 istanze più piccole | 2 istanze più piccole | *"SMOKE TEST SU CLUSTER — Verifica la sottomissione e i runscript distribuiti su un subset ridotto"* |
| `4_run_benchmark_hpc.sh` | 300 s | tutte le istanze canoniche (`benchmarks.bak`) | tutte | tutte | *"SUITE COMPLETA DISTRIBUITA SU CLUSTER"* |

Guardando i grafici in `test_folder/clingo_hpc_graphs/`: BSP copre **esattamente N=3,4,5**; PUP copre **esattamente 2 taglie** (N=20 e N=40); HRP copre **esattamente 2 taglie** (N=2 e N=4 persone). Questo combacia al millimetro con le costanti `SHORT_BSP_START=3`, `SHORT_BSP_END=5`, `SHORT_PUP_COUNT=2`, `SHORT_HRP_COUNT=2` dello script 3, e non ha alcuna relazione con lo script 4 (che userebbe l'intero set canonico e un timeout 20 volte più lungo).

**Conclusione: i grafici in `clingo_hpc_graphs/` sono il risultato dello smoke test, non della campagna completa.** Lo script 3 stesso lo dice in chiaro nel suo output finale ("Smoke test sottomesso! [...] Quando la coda si svuota, faremo lo script 4"): il passo successivo previsto era proprio lanciare la suite completa, che a quanto pare non è stata ancora eseguita (o è stata eseguita ma non è quella che ha prodotto queste cartelle — da verificare, ma i nomi/valori tornano troppo bene con lo script 3 per essere un caso).

**Da fare prima di scrivere qualsiasi risultato PUP/HRP in tesi**: lanciare `4_run_benchmark_hpc.sh` e rigenerare i grafici. Tutto quello che segue va quindi letto come "cosa ci dicono questi grafici-verifica-impianto", non come "risultati sperimentali di PUP e HRP".

---

## 4. Analisi dettagliata dei grafici

### 4.1 Le tabelle "Verdetto" (`_verdict.png`, comparison-native-prolog, tutte e tre le famiglie)

Le tre tabelle (BSP, PUP, HRP) sono **strutturalmente vuote**: intestazioni corrette ("Area / Variante / N / native / prolog / Migliore"), ma nessuna riga contiene dati — le celle sono bianche e la colonna "Migliore" mostra `n/d` per ogni area (solving/grounding/clingo_total/mem). C'è anche un difetto di layout: la scritta "RIASSUNTO PER ARE[A]" è troncata e sovrapposta alla prima riga della tabella, segno che il testo del sottotitolo è più largo della colonna e va gestito con un wrap o un font più piccolo.

**Cosa dovrebbe dire questo grafico**: per ciascuna area (solving, grounding, clingo_total, mem) e per l'ultima taglia N in comune tra i due backend, il tempo/memoria di native vs prolog e quale dei due vince. È l'unico riepilogo sintetico automatico dell'intera comparazione — quindi vale la pena sistemarlo, non solo per estetica: è quello che si guarda per primo.

**Causa più probabile**: la funzione che genera il verdetto probabilmente fa un join/lookup sulla "ultima taglia comune" tra i due sistemi, e se per una qualunque variante quella taglia non ha dati per uno dei due backend (vedi §4.3, i lazy-Prolog mancano quasi ovunque), il join fallisce silenziosamente e produce righe vuote invece di un errore o di un fallback ("N/D con nota"). Da controllare nello script che genera `_verdict.png` (probabilmente in `tools/plot_results.py` o uno script gemello dedicato al confronto).

### 4.2 BSP — confronto native vs prolog (N = 3, 4, 5)

I quattro grafici (`clingo_total`, `grounding`, `mem`, `solving`) raccontano la stessa storia: a queste taglie **tutto è sotto la risoluzione utile della misura**. `solving.png` è una linea piatta a 0.000s per tutte e quattro le serie attese in legenda — sensato, perché con n=3..5 BSP si risolve in microsecondi, ben sotto la granularità del timer di `runlim`/clasp. `clingo_total.png` e `grounding.png` sono identici (0.001–0.003s, due soli valori distinti su tre punti N), il che è coerente: se il solving è ~0, il tempo totale è quasi tutto grounding, esattamente come nella campagna BSP a n grandi (dove la tesi nota che il tempo non-solving domina), solo che qui la causa è opposta (tempi troppo piccoli, non grounding pesante).

Punto degno di nota anche se a scala minuscola: nel grafico `clingo_total`/`grounding` la curva "G&S Clingo · native" (rosso) sale sopra "Lazy Clingo · native" (viola) tra N=4 e N=5 (0.002s → 0.003s vs 0.001s → 0.002s), nella direzione attesa dalla tesi (il ground esplode più in fretta). Ma con soli 3 punti e valori a livello di millisecondo arrotondato, non è altro che un indizio direzionale, non un dato.

`mem.png` è **piatto a zero per tutte le taglie**, con un difetto grafico vistoso: l'asse Y mostra le etichette `0, 0, 0, -0, -0` invece di valori reali in GB. A queste taglie il processo consuma probabilmente qualche decina di MB, che arrotondati a GB con 2 cifre decimali diventano 0.00 — e il "-0" indica che la funzione di formattazione dei tick sta anche perdendo il segno su valori vicinissimi a zero (bug di arrotondamento/simmetria nella scala, non un problema di dati). **Da sistemare**: usare MB invece di GB quando il picco di memoria è sotto qualche centinaio di MB, o quantomeno filtrare i tick duplicati/con segno spurio.

Il pannello "Lazy Alpha · native" (verde) non compare mai visibilmente in nessuno dei 4 grafici comparison — combacia con quanto trovato nella dashboard nativa (§4.3): a queste taglie i tempi di `la` sono talmente vicini a `lc`/`gc` da sovrapporsi nella grafica, non un dato mancante.

### 4.3 BSP — dashboard "native" vs dashboard "prolog"

Qui emerge una differenza strutturale importante, non solo di scala. La dashboard **native** (`graphs-native/1_BSP/_dashboard.png`) mostra tutte le 8 varianti previste dal runscript per BSP: `gc_noheur, gc, ga, ga_weak, la, lc, la_aux, la_co`. La dashboard **prolog** (`graphs-prolog/1_BSP/_dashboard.png`) mostra **solo 4 varianti**: `gc_noheur, gc, ga, ga_weak` — **mancano completamente `la`, `lc`, `la_aux`, `la_co`**, cioè tutte le varianti che userebbero il motore SWI-Prolog lazy.

Questo non è un artefatto di scala: è un'assenza di dati. Il runscript (`runscript.xml`) definisce esplicitamente i setting `la`/`lc` anche per il sistema `clingo-prolog` (l'ho verificato riga per riga), quindi non è un problema di configurazione — le run per `la`/`lc` su Prolog per BSP **non hanno prodotto risultati validi** in questo smoke test. Le cause plausibili, da controllare nei log grezzi di `runlim`/btool prima di rilanciare qualunque cosa:

- il timeout di 15s dello smoke test è scattato per l'overhead fisso di avvio del motore SWI-Prolog in-process (la tesi stessa lo segnala come costo fisso indipendente da n — con un timeout così aggressivo potrebbe non bastare nemmeno per n=3);
- il fallback silenzioso del backend Prolog documentato nella tesi (§2.4.3, "silent-fallback failure mode": senza `LAZY_HEURISTIC_BACKEND=prolog` il backend degrada al valutatore ausiliario, che per le regole in stile Prolog fallisce silenziosamente) — anche se il wrapper dovrebbe esportare quella variabile automaticamente, vale la pena ri-verificarlo sull'ambiente cluster specifico;
- un errore di esecuzione (crash, libreria SWI non trovata sui nodi di calcolo, path del binario) che btool avrebbe classificato come run fallita e quindi omessa dal grafico.

Lo stesso pattern (variante lazy-prolog assente) si ripete identico su **PUP** (§4.4) e su **HRP** (§4.5): non è un caso isolato di BSP, è sistemico su tutte e tre le famiglie in questo run. Questo è probabilmente il problema più urgente da risolvere prima della full run, perché altrimenti si rifà un run da 300s di timeout e si scopre la stessa lacuna solo alla fine.

### 4.4 PUP (N = 20, 40) — l'unico caso con segnale già leggibile

Nonostante le taglie minuscole, PUP è l'unica famiglia in cui i grafici mostrano curve nettamente separate e sensate, probabilmente perché PUP satura più in fretta (istanze "double/doubleV" più dense di BSP a parità di N piccolo). Alcune osservazioni:

- **Grounding e memoria** (`graphs-native/2_PUP/_dashboard.png`, e `graphs-comparison-native-prolog/2_PUP/{grounding,mem}.png`): "G&S Clingo" (ground, con euristica) è già ~3× più costoso in grounding e ~2.5× in memoria rispetto al baseline `gc_noheur` a N=20, e il divario si allarga a N=40 (6.4s vs 1.2s di grounding; 0.49 GB vs 0.10 GB di picco RSS). Questo è coerente con l'aspettativa della tesi: l'euristica PUP moltiplica quattro domini di valori non srotolati, quindi l'esplosione combinatoria del ground si vede anche a N piccoli. È il primo indizio quantitativo, per quanto preliminare, che il fenomeno Θ(n³)-like di BSP si riproduce anche su PUP.
- **Il segnale più interessante**: nel grafico comparison `solving.png` e nella dashboard nativa, "Lazy Clingo · native" (`lc`) passa da ~0.3s a N=20 a **~88s a N=40** — un salto di quasi 300× per un raddoppio della taglia, mentre "G&S Clingo" passa da ~1.3s a ~2.3s (quasi lineare) e "Lazy Alpha" (`la`) resta vicino a zero per entrambe le taglie. Questo è l'opposto del quadro BSP, dove `lc` restava vicino al baseline: qui `lc` nativo è **il peggiore in assoluto**, di gran lunga. **Non scriverei questo in tesi allo stato attuale** (due punti non bastano per distinguere un salto di soglia da una vera esplosione esponenziale, e il fix di flattening del 2 luglio riguarda proprio `lc` nativo su PUP — va verificato che il dato che vedo qui sia già post-fix), ma è un campanello d'allarme concreto da tenere d'occhio nella full run: se si conferma, sarebbe un risultato scientificamente interessante (un caso in cui la semantica clingo-like "onesta" del lazy costa più del ground, non solo meno del greedy `la`), ma richiede più punti (N=25, 30, 35) per essere caratterizzato prima di essere raccontato.
- Come per BSP, la dashboard `graphs-prolog/2_PUP/_dashboard.png` non ha alcuna serie lazy (`la`/`lc`): stessa lacuna sistemica del §4.3.

### 4.5 HRP (N = 2, 4 persone) — dati non informativi

Tempi in millisecondi (3-9 ms), memoria piatta a zero con lo stesso bug di tick "0/-0" di BSP. A N=2..4 persone il problema HRP è quasi banale per il solver: tutte le curve di "Solving Time" sono a 0.000s, e le differenze fra le varianti nelle altre metriche (rules, variables, atoms, constraints) sono presenti ma di entità minima (centinaia contro migliaia di regole, non milioni come servirebbe per vedere l'effetto). **Nessuna conclusione è estraibile da questi due punti**: servono le istanze HRP "vere" (quelle usate nella campagna che la tesi cita come già pronte) per dire qualcosa. Anche qui, dashboard Prolog priva delle varianti lazy.

### 4.6 Checklist bug/anomalie da sistemare prima del prossimo run

1. **Tabella verdetto vuota** (tutte e 3 le famiglie) — il join taglia-comune produce righe senza dati; va reso robusto o va emesso un messaggio esplicito invece di celle bianche + `n/d`.
2. **Overlap testo "RIASSUNTO PER ARE(A)"** sopra l'intestazione della tabella verdetto — bug di layout/font width.
3. **Serie lazy-Prolog (`la`, `lc`, e su BSP anche `la_aux`/`la_co`) assenti in tutte e 3 le dashboard `graphs-prolog/*`** — non un bug di plotting ma di dati: da investigare nei log grezzi di btool/runlim prima del prossimo lancio, altrimenti si rischia di riscoprirlo dopo 300s×N_istanze di attesa sul cluster.
4. **Asse memoria con tick duplicati "0/-0"** su BSP e HRP (`mem.png`, sia comparison sia dashboard) — probabile bug di formattazione quando tutti i valori sono sotto la risoluzione della scala in GB; considerare un'unità adattiva (MB) sotto una certa soglia.
5. **Range di N troppo piccolo per essere utile in un grafico "risultati"** — per costruzione questo è uno smoke test, quindi non è un bug, ma va assicurato che questi grafici non finiscano per errore nella cartella che alimenta la tesi (rischio concreto di confusione, visto che le cartelle `graphs-native/graphs-prolog/graphs-comparison-native-prolog` hanno lo stesso nome sia per lo smoke test sia per la full run, a giudicare dagli script).
6. **Verifica post-fix**: confermare che i dati PUP/HRP `lc` nativo qui analizzati incorporino davvero il fix di flattening del 2 luglio (la data dei file, 7 luglio, lo suggerisce, ma vale la pena un controllo diretto sull'encoding effettivamente usato nel run, es. hash/diff di `PUP_lc.lp` al momento del lancio).

---

## 5. Discussione preliminare (work in progress)

**Cosa possiamo dire con certezza oggi**: esattamente quello che diceva già la tesi prima di questa sessione. BSP locale è completo e solido; PUP e HRP restano "cablati, in attesa dei numeri definitivi". Lo smoke test HPC appena analizzato non cambia questo stato — semmai lo conferma, mostrando che l'infrastruttura di sottomissione cluster e di plotting *funziona* (i grafici si generano, i dati fluiscono da btool a matplotlib), il che è comunque un risultato positivo e non scontato per una pipeline distribuita su SLURM.

**Segnali preliminari, da NON mettere ancora in tesi**: (a) su PUP, l'esplosione di grounding/memoria per le varianti ground-and-solve sembra riprodursi anche a N piccoli, in linea con l'aspettativa teorica; (b) sempre su PUP, `lc` nativo mostra un rallentamento drammatico da N=20 a N=40 che meriterebbe una caratterizzazione con più punti — se confermato dalla full run, sarebbe un risultato scientificamente rilevante (un caso concreto in cui la semantica "onesta" clingo-like del propagatore lazy costa più caro del ground stesso, non solo meno del greedy Alpha-like), da inquadrare accanto al trade-off spazio-tempo già discusso in §3.9 della tesi.

**Rischio metodologico da evitare**: scrivere risultati PUP/HRP nella tesi sulla base di questi grafici sarebbe un errore, per almeno tre motivi indipendenti — taglie non rappresentative (N=20/40 e N=2/4 contro le decine/centinaia previste), dati mancanti per un'intera famiglia di varianti (lazy Prolog), e incertezza sul se il fix di flattening del 2 luglio sia davvero incorporato nel run che ha prodotto questi file. Meglio aspettare la full run e trattare questo documento come il verbale di un controllo pre-volo.

---

## 6. Prossimi passi concreti

1. Prima di rilanciare: capire perché le varianti lazy-Prolog non producono dati (log grezzi runlim/btool per almeno una run `la`/`lc` su Prolog, su tutte e tre le famiglie).
2. Sistemare la tabella verdetto (join vuoto) e il bug dei tick di memoria — piccoli fix allo script di plotting, non richiedono un nuovo run per essere testati (si può rigenerare dai `results.xml` dello smoke test già disponibili).
3. Lanciare `4_run_benchmark_hpc.sh` (timeout 300s, istanze canoniche) una volta risolto il punto 1, altrimenti si ripete la stessa lacuna su scala enormemente più costosa in tempo di coda SLURM.
4. Per PUP, valutare se aggiungere 2-3 taglie intermedie (N=25, 30, 35) rispetto al solo `double`/`doubleV` minimo, per caratterizzare meglio l'andamento di `lc` nativo prima di darlo per assodato.
5. Solo a quel punto: aggiornare `3 - Risultati.tex` e `4 - Discussione-e-Conclusione.tex` della tesi ufficiale con le sezioni PUP/HRP, seguendo lo stesso stile (formule esatte dove possibile, tabelle a taglia fissa + figura, caveat espliciti sulle metriche) già usato per BSP.

---

## 7. Mappa dei file (riferimento rapido)

- Tesi ufficiale (inglese, LaTeX): `thesis/Tesi_Lazy_Heuristics/*.tex`
- Audit di codice/encoding del 2 luglio: `docs/AUDIT-2026-07-02.md`
- Script smoke test cluster: `3_run_benchmark_short_hpc.sh` (quello che ha prodotto i grafici analizzati qui)
- Script full run cluster: `4_run_benchmark_hpc.sh` (ancora da lanciare, a quanto risulta)
- Grafici analizzati in questo documento: `test_folder/clingo_hpc_graphs/{graphs-native,graphs-prolog,graphs-comparison-native-prolog}/{1_BSP,2_PUP,3_HRP}/*.png`
- Runscript btool: `test_folder/benchmark_folder_clingo/runscripts/runscript.xml`
