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
7. **Aggiornamento della stessa giornata (vedi §9)**: individuato e corretto il bug che causava lo smoke test "fantasma" (runlim compilato sul login node invece che su un compute node → fallimento silenzioso, 0 run realmente eseguiti). Dopo il fix, la pipeline funziona end-to-end (67/88 run risolti). Ma è emerso un problema **nuovo e sistemico**: tutte le 20 run che usano il backend Prolog con una variante lazy (`la`/`lc`/`la_aux`/`la_co`) falliscono per timeout esatto, indipendentemente dalla taglia dell'istanza (fallisce anche `house-2`, il caso più piccolo possibile) — mentre lo stesso backend Prolog funziona perfettamente sulle varianti ground-and-solve. Non è quindi "il backend Prolog è lento", è "il percorso lazy via Prolog si blocca sul cluster" — probabile problema ambientale (libreria SWI-Prolog sui compute node), ancora da confermare con i log grezzi. **Conclusione invariata rispetto al punto 4: PUP/HRP non sono ancora scrivibili in tesi**, per una ragione aggiuntiva ora identificata.

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

---

## 9. Aggiornamento — 7 luglio, sessione fix runlim/glibc + rilancio smoke test

Aggiornamento successivo alla Sezione 8. Nella stessa giornata è stato individuato e risolto il bug che causava lo "smoke test fantasma" del §3.2/§4: `runlim` veniva compilato **sul login node** da `ensure_runlim`, ma i job SLURM girano sui compute node; se la glibc diverge, l'`exec` di `runlim` falliva con `GLIBC_x.xx not found` — ma siccome `templates/seq-generic.sh` non ha `set -e`, il run finiva comunque `.finished` senza `runsolver.watcher`, e btool lo marcava silenziosamente come "non risolto" invece che come errore. Sintomo osservato quel giorno: **100% degli 88 run dello smoke test con `timeout=1, time=15` e 0 `error=1`** — cioè nessun run aveva davvero eseguito clasp. Fix applicato: ricompilazione di `runlim` dentro una sessione interattiva `srun --partition=kr --pty bash` (compute node), non sul login node. Vedi anche [[benchmark-tool-setup]] (memoria di progetto) per la cronologia completa del fix.

Dopo il fix, `3_run_benchmark_short_hpc.sh` + `5_evaluate_hpc.sh` sono stati rilanciati e i nuovi `results.xml`/`results.xlsx`/grafici (in `clingo_hpc_graphs/`, timestamp 7 luglio 13:02) sono stati riscaricati in locale. Ho riletto `results.xml` riga per riga (88 run, non solo i grafici) e ricontrollato due delle ipotesi della Sezione 8. Ecco cosa cambia.

### 9.1 Due bug della Sezione 8 risultano già corretti — verificato sul codice attuale

- **§8.1 (timeout distjob non patchato)**: **falso allo stato attuale**. Ho riletto `scripts/bench_common.sh::derive_runscript` di persona: patcha **sia** `<seqjob>` **sia** `<distjob>`:
  ```python
  for sj in r.findall("seqjob"):
      sj.set("timeout", os.environ["RS_TIMEOUT"])
  for dj in r.findall("distjob"):
      dj.set("timeout", os.environ["RS_TIMEOUT"])
  ```
  Prova empirica indipendente: nel nuovo `results.xml` tutti i run in timeout mostrano `time=15` esatto (non 600) — il timeout da 15s dichiarato in `3_run_benchmark_short_hpc.sh` è realmente quello applicato sul cluster. Il bug descritto in §8.1 non è più presente (probabilmente già corretto tra la stesura della Sezione 8 e questa sessione).
- **§8.3 (range BSP canonico ridotto a n=3..30)**: **falso allo stato attuale**. `test_folder/benchmark_folder_clingo/benchmarks/BSP` contiene oggi 12 istanze, `bsp-0010.lp` .. `bsp-0120.lp` (step 10) — esattamente il range n=10..120 della tesi (§3.2). `benchmarks.bak/` continua a non esistere, ma non serve: il set "vivo" è già quello giusto. Anche PUP (`double-20`..`double-200`, step 20, 10 istanze) e HRP (`house-2`..`house-20`, step 2, 10 istanze) sono a posto. **Nessuna azione richiesta qui**: `4_run_benchmark_hpc.sh`, quando lanciato, userà il range corretto.

### 9.2 La pipeline ora funziona end-to-end: dati reali, non più solo timeout

`results.xml` (88 run): **67 SATISFIABLE, 21 UNKNOWN (timeout), 0 error**. Le dashboard `graphs-native` e `graphs-prolog` mostrano curve reali (tempi, RSS, scelte, conflitti) invece di essere tutte a zero/assenti. La pipeline btool→xlsx→plot funziona; il problema non era più infrastrutturale in senso stretto.

### 9.3 Scoperta nuova: fallimento sistemico e uniforme del backend Prolog su TUTTE le varianti lazy, indipendente dalla taglia

Questo è il fatto più importante emerso oggi, e va tenuto ben distinto dal bug runlim/glibc (quello era "nessun run gira", questo è "un sotto-insieme preciso di run non gira mai, size-indipendente"):

**Tutti** i run con `system=clingo-prolog` e `setting ∈ {la, lc, la_aux, la_co}` — 20 run su 20, su tutte e tre le famiglie, **comprese le istanze più piccole possibili** (`bsp-0003`, `house-2`) — risultano `status=UNKNOWN, time=15` (timeout esatto). Dettaglio:

| Famiglia | Setting Prolog lazy falliti | Istanze | Esito |
|---|---|---|---|
| BSP | la, lc, la_aux, la_co | bsp-0003, bsp-0004, bsp-0005 | 12/12 timeout |
| PUP | la, lc | double-20, double-40 | 4/4 timeout |
| HRP | la, lc | house-2, house-4 | 4/4 timeout |

Punti a favore dell'ipotesi "hang deterministico", non "istanza troppo grande":
- **Nessuna dipendenza dalla taglia**: `house-2` (2 persone, il problema HRP più piccolo possibile) fallisce esattamente come `house-4`. Se fosse un problema di scala ce lo aspetteremmo solo sulle istanze più grandi.
- **Il grounding completa regolarmente** (`grounding` riporta valori piccoli e sensati, es. 0.001–2.2s, coerenti con le controparti native/ground-and-solve) — il propagatore Prolog non impedisce il grounding, si blocca dopo.
- **`solving=0.0` esatto** su quasi tutti (eccetto PUP `la`/`lc`@40 dove il processo ha comunque accumulato RSS reale, 206 MB — segno che il processo SWI-Prolog è vivo e alloca memoria, ma non progredisce mai fino a produrre un modello).
- Le stesse istanze, stesso backend Prolog, ma con setting **ground-and-solve** (`gc_noheur`, `gc`, `ga`, `ga_weak`) **funzionano perfettamente** e con tempi quasi identici al backend native (es. BSP `gc` bsp-0005: native 0.02s vs prolog 0.03s). Quindi non è il binario `clingo-prolog` in sé a essere rotto (l'`exec` funziona, il grounding gringo funziona) — è specificamente il **percorso runtime del propagatore lazy via SWI-Prolog** (invocato solo da `la`/`lc`/`la_aux`/`la_co`) a bloccarsi sul cluster.

**Da NON confondere con l'anomalia PUP `lc` nativo (già notata in §4.4)**: quella (`clingo-native`, PUP, `lc`, `double-40`) è l'**unica** eccezione tra i 21 timeout con un profilo diverso — `solving=12.98s` (non 0), `grounding=2.01s`, cioè il solver ha davvero lavorato per 13 secondi buoni prima di essere abbattuto dal timeout. È un genuino segnale di rallentamento a scala (coerente con quanto ipotizzato in §4.4, ora con un timeout reale confermato a 15s anziché l'ipotizzato-erroneamente-600s), **non** lo stesso fenomeno del blocco Prolog. Da tenere d'occhio nella full run con più punti (N=25,30,35 come già suggerito al §6), ma resta un'ipotesi, non un fatto assodato (due punti soli: 0.39s a N=20, timeout a N=40).

**Causa probabile del blocco Prolog** (da confermare, non ancora certa): qualcosa nell'inizializzazione o nella prima invocazione a runtime del motore SWI-Prolog in-process si blocca in modo deterministico sui compute node del cluster kr — indipendente dalla taglia del problema. Candidati plausibili, in ordine di probabilità: (a) libreria/dipendenza di SWI-Prolog mancante o incompatibile sui compute node (stessa classe di problema di `runlim`, ma questa volta sul runtime SWI incorporato nel backend, non sul limitatore) — l'`exec` iniziale del binario riesce (il grounding lo dimostra), ma la chiamata alla libreria SWI a runtime fallisce/si blocca; (b) un problema di ambiente specifico al nodo di calcolo (variabili d'ambiente, permessi `/tmp`, thread affinity con `cpt=4`) che impedisce l'avvio del motore Prolog embedded; (c) un deadlock nel binding C++↔Prolog del propagatore stesso, indipendente dal cluster (ma allora ci si aspetterebbe lo stesso comportamento anche in locale, il che andrebbe verificato per escluderlo).

**Prossimo passo concreto per diagnosticare (costa zero, i dati grezzi esistono già sull'HPC)**: ispezionare l'output grezzo di una delle run bloccate, per esempio:
```bash
cd ~/clingo-lazy-heuristics/test_folder/benchmark_folder_clingo/output-short-hpc/study-hpc/hpc/results/BSP/clingo-prolog-1.0-la/bsp-0003/run1
cat runsolver.solver     # stdout+stderr del wrapper, catturati da seq-generic.sh
cat runsolver.watcher    # report runlim: tempo reale, motivo dell'abbattimento
```
Se `runsolver.solver` è vuoto o si interrompe subito dopo il grounding senza errori, è compatibile con (a)/(b) — un hang silenzioso all'avvio del motore SWI. Se mostra un errore di libreria (`error while loading shared libraries`, `cannot find`, ecc.) conferma (a) e si risolve ricompilando/verificando SWI-Prolog sullo stesso compute node (stessa procedura usata per `runlim`: `srun --partition=kr --pty bash`, poi verifica/ricompila).

### 9.4 I bug di plotting della checklist §4.6 — stato verificato oggi

Ho riaperto `graphs-prolog/1_BSP/_dashboard.png` e `graphs-comparison-native-prolog/2_PUP/_verdict.png` coi dati nuovi:

- **Tabella verdetto ancora vuota** (checklist #1): confermato, ancora presente. Intestazioni corrette, righe bianche, colonna "Migliore" = `n/d` ovunque.
- **Overlap testo "RIASSUNTO PER ARE(A)"** (checklist #2): confermato, ancora presente, si sovrappone alla prima riga della tabella.
- **Asse memoria con tick "0/-0" duplicati** (checklist #4): confermato, ancora presente sulla dashboard BSP (sia native sia prolog) — valori reali sotto la risoluzione della scala in GB.
- **Serie lazy-Prolog assenti dalle dashboard `graphs-prolog/*`** (checklist #3): **non è più un bug di plotting da correggere — è la rappresentazione corretta del fenomeno del §9.3.** Quei run ora *esistono* in `results.xml` con status `UNKNOWN`, quindi lo script di plotting li esclude giustamente dai grafici (non ci sono un tempo/mem di un run risolto da disegnare). Non c'è nulla da sistemare in `plot_results.py` su questo punto specifico; il problema è a monte (perché quei run falliscono), non nello script di grafici.

Nessuna di queste tre voci residue blocca la lettura dei dati BSP/PUP/HRP raccolti finora, ma la tabella verdetto sarebbe comunque utile da sistemare prima della full run, visto che è il riepilogo che si guarda per primo.

### 9.5 Verdetto aggiornato su "possiamo scrivere risultati PUP/HRP in tesi adesso?"

**No, ancora no** — per una ragione aggiuntiva rispetto a quelle già valide del §5 (taglie non rappresentative: N=3..5/20,40/2,4 contro i range canonici n=10..120/20..200/2..20 ora disponibili nei benchmark). La ragione nuova: **un'intera colonna sperimentale (backend Prolog × varianti lazy) fallisce sistematicamente al 100%** in questo smoke test. Scrivere oggi un confronto "native vs prolog" per le varianti lazy su PUP/HRP significherebbe basarlo su dati che sono, con altissima probabilità, un artefatto ambientale del cluster (vedi §9.3) e non un risultato scientifico (es. "il backend Prolog è troppo lento" sarebbe una conclusione sbagliata: il backend Prolog *funziona* perfettamente sulle varianti ground-and-solve, quindi non è "lento", è **bloccato** specificamente sul percorso lazy). Riportarlo in tesi così com'è rischierebbe di introdurre una conclusione falsa che poi va ritrattata.

**Prima di lanciare `4_run_benchmark_hpc.sh` (full run, 300s/istanza dichiarati, range canonico già corretto)**: risolvere il punto del §9.3, altrimenti si spende budget di coda SLURM enormemente maggiore (300s reali invece di 15s, e ~10× più istanze per famiglia) per riscoprire esattamente lo stesso fallimento sistemico sulle varianti lazy-Prolog, questa volta però su ogni taglia del dataset canonico.

---

## 8. Analisi degli script di lancio (`1_..sh` .. `5_evaluate_hpc.sh`) e `bench_common.sh`

Aggiornamento dell'8 luglio: ho riletto per intero i cinque script numerati in root e `test_folder/benchmark_folder_clingo/scripts/bench_common.sh` (nel frattempo è comparso anche un quinto script, `5_evaluate_hpc.sh`, che raccoglie ed elabora i risultati del cluster — non esisteva quando ho scritto la Sezione 4). Ho trovato due bug concreti, uno dei quali spiega meglio le anomalie della Sezione 4, e correggo un'ipotesi che avevo fatto lì.

### 8.1 BUG — il timeout dichiarato per l'HPC (script 3 e 4) non ha alcun effetto reale

`bench_common.sh::derive_runscript` (righe 99-123) patcha il timeout **solo sugli elementi `<seqjob>`**:

```python
for sj in r.findall("seqjob"):
    sj.set("timeout", os.environ["RS_TIMEOUT"])
```

Non tocca mai `<distjob>`. Ora, `runscript.xml` definisce due job distinti: `seqjob name="seq-local" timeout="300s"` (usato dal progetto `study-local`, cioè gli script 1 e 2) e `distjob name="dist-hpc" timeout="600s" ... partition="kr"` (usato dal progetto `study-hpc`, cioè gli script 3 e 4). Il template SLURM (`templates/single.dist`) usa `{walltime}` solo per il budget di coda (`#SBATCH --time=`), mentre il timeout per-istanza passato a `runlim --real-time-limit={timeout}` (`templates/seq-generic.sh`, riga 12) viene sempre risolto dall'attributo `timeout` del job che genera quella run — per `study-hpc` è sempre `dist-hpc`, mai `seq-local`.

**Conseguenza**: `TIMEOUT=15` in `3_run_benchmark_short_hpc.sh` e `FULL_TIMEOUT=300` in `4_run_benchmark_hpc.sh` sono **variabili morte per il cluster**: qualunque cosa lanci con questi due script gira sempre con il timeout hardcoded di `runscript.xml`, cioè **600 secondi per istanza**, non 15 né 300. Lo smoke test non ha mai davvero avuto un timeout da 15s; se una run si fosse impallata per un problema di ambiente (vedi 8.2), avrebbe comunque consumato fino a 10 minuti di coda invece di essere abbattuta in 15s. E la "suite completa" HPC (script 4), quando la lancerai, girerà con timeout reale doppio (600s) rispetto alla sua gemella locale (script 2, che invece patcha correttamente `seq-local` a 300s) — le due campagne non sarebbero direttamente confrontabili sul piano del timeout.

**Fix**: in `derive_runscript`, aggiungere anche `for dj in r.findall("distjob"): dj.set("timeout", os.environ["RS_TIMEOUT"])`. Va fatto prima di rilanciare qualsiasi cosa sull'HPC, altrimenti si spreca budget di coda SLURM inutilmente.

### 8.2 Rettifica alla Sezione 4: perché mancano i dati lazy-Prolog (`la`/`lc`) nello smoke test

Nella Sezione 4.3 avevo ipotizzato che il timeout di 15s potesse essere la causa della mancanza delle varianti lazy-Prolog nelle dashboard `graphs-prolog/*`. Alla luce dell'8.1, questa ipotesi **va scartata**: il timeout reale era 600s, ampiamente sufficiente per istanze di quella taglia. La causa è quindi più probabilmente un fallimento a runtime (crash, non un timeout), e l'audit del 2 luglio (`docs/AUDIT-2026-07-02.md`, punto 5 delle osservazioni sul repo) segnala un rischio già noto e coerente con questo sintomo: **i binari in `clingo-*/build/bin` sono linkati a glibc 2.38**, e qualunque verifica in un ambiente con libc diversa (es. i nodi di calcolo del cluster, se hanno un'immagine diversa dal nodo dove hai compilato/sottomesso) richiede una ricompilazione. Un mismatch di questo tipo sul motore SWI-Prolog in-process (linkato staticamente nel backend Prolog) fallirebbe silenziosamente all'avvio, senza produrre un `.finished` utile e senza comparire nei grafici — esattamente il sintomo osservato (nessuna riga per `la`/`lc` in nessuna delle tre famiglie sul backend Prolog).

**Da fare prima di rilanciare**: i dati grezzi dello smoke test esistono già e non costano nulla da controllare. Vai in `output-short-hpc/study-hpc/hpc/.../clingo-prolog/la/...` (o l'equivalente cartella per una qualunque istanza BSP/PUP/HRP, setting `la` o `lc`, sistema `clingo-prolog`) e guarda `runsolver.solver` (stderr+stdout catturati) e gli `err.%j`/`out.%j` di sbatch nella cartella del job SLURM corrispondente. Se vedi un errore di linking (`error while loading shared libraries`, o simili) è confermato il sospetto dell'audit, e la soluzione è ricompilare `clingo-prolog` (`REBUILD_CLINGO=1`) *sul/per il nodo di calcolo*, non solo sul nodo di submission.

### 8.3 Regressione dati — il set BSP "canonico" attuale non copre il range della tesi

`restore_canonical_instances` (in `bench_common.sh` per gli script 1/2, e duplicata inline in script 3/4) cerca prima `benchmarks.bak/`, e ripiega su `benchmarks/` se assente. **`benchmarks.bak/` non esiste** in questo checkout (verificato: `[ -d benchmarks.bak ]` → falso). Quindi ogni run "canonico" (script 2 e 4) userà semplicemente quello che c'è oggi in `test_folder/benchmark_folder_clingo/benchmarks/`:

- BSP: 28 istanze, `bsp-0003.lp` .. `bsp-0030.lp` (n = 3..30)
- PUP: 10 istanze, `double-20.asp` .. `double-200.asp` (N = 20..200, passo 20)
- HRP: 10 istanze, `house-2.asp` .. `house-20.asp` (N = 2..20, passo 2)

Il problema è **BSP**: la tesi (§3.2, Tabella "Experimental Dataset") riporta la campagna completa su **n = 10..120**, con i primi timeout proprio intorno a n=110-120 — cioè esattamente la parte più interessante della curva (dove Θ(n³) supera l'overhead fisso del motore Prolog, il crossover di cui parla la Discussione). Il set attuale si ferma a **n=30**: se lanci `2_run_benchmark_full.sh` o `4_run_benchmark_hpc.sh` così come sono, **non riproduci il dataset della tesi per BSP, lo restringi drasticamente**, perdendo proprio la parte della curva dove si vede il crossover.

**Fix prima di rilanciare la full (locale o HPC)**: rigenerare le istanze BSP canoniche con `tools/gen_bsp_instances.py --out benchmarks/BSP --start 10 --end 120 --step 10 --clean` (o il passo che preferisci), oppure recuperare/ricostruire un `benchmarks.bak/BSP` con il range giusto, così che sia lo script 2 (locale, per verificare prima in economia) sia lo script 4 (HPC) partano dal range corretto. PUP e HRP invece sembrano già coerenti con quanto la tesi dà per "cablato e pronto" (10 istanze ciascuno, range ragionevole) — nessuna azione necessaria lì.

### 8.4 Osservazioni minori

- `5_evaluate_hpc.sh` (Fase 4) chiama `tools/plot_results.py --machine hpc --out-base ..` **senza** `--ground-counts`, a differenza di `run_btool_pipeline` in `bench_common.sh` (usata dagli script 1/2) che lo passa automaticamente se `ground_counts.csv` esiste. Inoltre **nessuno script lancia mai `tools/ground_counts.py`**: è uno strumento disaccoppiato, va invocato a mano. Risultato pratico: i grafici prodotti dalla pipeline HPC non includeranno mai il conteggio esatto delle direttive ground (quello dietro al grafico `combined_heuristics`/Θ(n³) della tesi) a meno di generare il CSV a mano e modificare lo script 5 per passarlo.
- `5_evaluate_hpc.sh` sceglie il runscript da valutare così: se esiste `runscript.full.xml` usa quello, altrimenti ripiega su `runscript.short_hpc.xml`. È il motivo esatto per cui i grafici analizzati in Sezione 4 sono quelli dello smoke test: al momento in cui hai lanciato lo script 5, `runscript.full.xml` non esisteva ancora (lo crea solo lo script 4, mai eseguito). Nessuna azione richiesta, solo conferma della diagnosi della Sezione 4.2 — comportamento corretto ma da tenere a mente: una volta lanciato lo script 4, lo script 5 preferirà sempre "full" anche se in futuro rivuoi rivalutare un nuovo smoke test.
- `benchmarks/_short/` è una cartella residua dentro `benchmarks/` lasciata da un run locale con lo script 1: innocua (nome isolato, non tocca BSP/PUP/HRP canonici) ma da ripulire per igiene, sulla falsariga di quanto l'audit del 2 luglio già segnalava per altri residui simili (`prova.lp`, `GC`, `BSP_tmp`).

### 8.5 Ordine consigliato delle prossime azioni

1. **Non rilanciare ancora `4_run_benchmark_hpc.sh`.** Prima applica il fix di 8.1 (`derive_runscript` deve patchare anche `<distjob>`), altrimenti si spreca coda SLURM con un timeout diverso da quello dichiarato.
2. Controlla i log grezzi dello smoke test già fatto (8.2) per confermare/escludere il mismatch glibc/SWI sul backend Prolog **prima** di rilanciare — costa zero, i dati esistono già.
3. Rigenera il set canonico BSP fino a n≈120 (8.3) così che la prossima full (locale o HPC) sia comparabile con la tesi.
4. Solo a quel punto: eventualmente un nuovo smoke test breve (`3_run_benchmark_short_hpc.sh`) per validare i tre fix a costo quasi nullo, poi `4_run_benchmark_hpc.sh` per la campagna vera, poi `5_evaluate_hpc.sh` per raccogliere/plottare.
5. Se vuoi anche il grafico di conteggio ground-heuristics stile tesi per PUP/HRP, lancia manualmente `tools/ground_counts.py` e passa il CSV risultante a `plot_results.py` (valuta di aggiungere `--ground-counts` anche dentro `5_evaluate_hpc.sh`, così diventa automatico).
