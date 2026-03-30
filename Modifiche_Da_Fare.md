1) perchè __heuristic_rule? preferirei che si chiamasse solo __heuristic

2) è davvero necessario passare un rule_id nell'atomo __heuristic?
penso che questa cosa sia solo maggiormente prona ad errori, penso sia meglio lasciare che sia il codice c++ ad estrarre tutti gli atomi __heuristic e magari discriminarli tra loro grazie al solver literal o whatever

3) in init_static_mode fai un for per estrarre le __heuristic???? ma in che senso??? la static mode sarebbe la classica modalità di clingo con 


#heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]

no? e allora che cos'è sta cosa __heuristic? fixa bene

4) non mi convince l'idea di avere "fissato" dentro __heuristic ad un parametro n gli atomi positivi e gli atomi negativi

questa cosa va bene per come è definita attualmente la struttura, ma potrebbe tranquillamente cambiare, per lo stesso motivo non mi piace che stiamo cercando delle __heuristic/7, e se in un problema mi servisse una regola heuristica con altri 5 atomi con segni diversi???

stavo pensando di discriminare gli atomi positivi da quelli negativi indicandoli ad esempio così:


__heuristic_rule(b, x, __n_c, self, __sum(c), true).

quindi come vedi non c'è l'id della regola e non è necessario posizionare gli atomi in una posizione 


__heuristic_rule(b, __n_c, x, self, __sum(c), true).

sarebbe equivalente

possiamo dire che solo la prima posizione è fissata, che ci specifica quale atomo scegliere, per il resto è tutto abbastanza flessibile dato che penso si possa discriminare tutto in automatico

__sum e gli altri aggregati sono chiari, 2 trattini e una keyword
i positivi non hanno nulla
i negativi hanno __n_ 
self è chiaro
i valori booleani sono chiari

5) 