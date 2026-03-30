1) è vero che al momenot controlli la direttiva __heuristic nel primo parametro e controlli se b è un simbolo privo di argomenti o meno per decidere se applciare il lazy grounding o no?

ti posso garantire che se in un encoding viene scritto __heuristic sicuramente serve l lazy grounding, per cui vorrei che controllassi se vale la pena o meno di fare questo controllo o se è un assunzione che si può dare per scontata risparmiando codice e semplificando la lgocia

2) è davvero necessario separare l'uso degli aggregati dinamici per livello da quelli per peso usando la keyword __w_? non c'è un modo per farlo "naturale"? semplicemente se l'aggregato dinamico viene assegnato ad una variabile tipo

s = __sum(b)

viene applicato alla variabile S? non so, dimmi tu

3) 