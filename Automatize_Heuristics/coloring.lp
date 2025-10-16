% --- Definizione del problema: Graph Coloring ---

% Colori disponibili (6 colori per grafi complessi)
color(red; green; blue; yellow; orange; purple).

% --- Regole del Graph Coloring (Hard Constraints) ---

% 1. Ogni nodo deve avere esattamente un colore.
{ color(N, C) : color(C) } = 1 :- node(N).

% 2. Due nodi adiacenti non possono avere lo stesso colore.
:- color(N1, C), color(N2, C), edge(N1, N2).
