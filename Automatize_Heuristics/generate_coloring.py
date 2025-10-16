#!/usr/bin/env python3
"""
Script per generare istanze di Graph Coloring in modo procedurale.
Crea grafi parametrici con garanzia di risolubilità.
"""

import random
import argparse
from typing import Set, Tuple, List


class GraphGenerator:
    """Generatore di grafi per problemi di Graph Coloring."""
    
    def __init__(self, num_nodes: int, num_colors: int, seed: int = None):
        """
        Inizializza il generatore di grafi.
        
        Args:
            num_nodes: Numero di nodi nel grafo
            num_colors: Numero di colori disponibili (limita il numero cromatico)
            seed: Seed per la generazione random (per riproducibilità)
        """
        self.num_nodes = num_nodes
        self.num_colors = num_colors
        self.edges: Set[Tuple[int, int]] = set()
        
        if seed is not None:
            random.seed(seed)
    
    def add_edge(self, u: int, v: int):
        """Aggiunge un arco non direzionale al grafo."""
        if u != v:
            # Mantieni sempre u < v per evitare duplicati
            edge = (min(u, v), max(u, v))
            self.edges.add(edge)
    
    def generate_clusters(self, num_clusters: int, connectivity: float = 0.7):
        """
        Genera un grafo a cluster con connettività interna controllata.
        
        Args:
            num_clusters: Numero di cluster da creare
            connectivity: Probabilità di connessione tra nodi nello stesso cluster (0-1)
        """
        nodes_per_cluster = self.num_nodes // num_clusters
        remainder = self.num_nodes % num_clusters
        
        print(f"Generazione di {num_clusters} cluster con ~{nodes_per_cluster} nodi ciascuno...")
        
        current_node = 1
        clusters = []
        
        # Crea i cluster
        for i in range(num_clusters):
            cluster_size = nodes_per_cluster + (1 if i < remainder else 0)
            cluster_nodes = list(range(current_node, current_node + cluster_size))
            clusters.append(cluster_nodes)
            
            # Connessioni interne al cluster
            for j in range(len(cluster_nodes)):
                for k in range(j + 1, len(cluster_nodes)):
                    if random.random() < connectivity:
                        self.add_edge(cluster_nodes[j], cluster_nodes[k])
            
            current_node += cluster_size
        
        # Connessioni tra cluster (più sparse)
        inter_cluster_connectivity = connectivity * 0.3
        for i in range(len(clusters)):
            for j in range(i + 1, len(clusters)):
                # Connetti alcuni nodi tra cluster diversi
                num_connections = max(1, int(len(clusters[i]) * 0.2))
                for _ in range(num_connections):
                    u = random.choice(clusters[i])
                    v = random.choice(clusters[j])
                    if random.random() < inter_cluster_connectivity:
                        self.add_edge(u, v)
        
        print(f"Generati {len(self.edges)} archi in struttura a cluster")
    
    def generate_ring_with_hubs(self, num_hubs: int):
        """
        Genera un grafo con un anello esterno e hub centrali connessi.
        
        Args:
            num_hubs: Numero di nodi hub centrali
        """
        if num_hubs >= self.num_nodes:
            raise ValueError("Numero di hub troppo alto rispetto ai nodi totali")
        
        print(f"Generazione di grafo con {num_hubs} hub e anello di {self.num_nodes - num_hubs} nodi...")
        
        # Hub centrali (nodi 1 a num_hubs)
        hubs = list(range(1, num_hubs + 1))
        
        # Connetti gli hub tra loro (clique)
        for i in range(len(hubs)):
            for j in range(i + 1, len(hubs)):
                self.add_edge(hubs[i], hubs[j])
        
        # Nodi dell'anello esterno
        ring_nodes = list(range(num_hubs + 1, self.num_nodes + 1))
        
        # Crea l'anello
        for i in range(len(ring_nodes)):
            next_i = (i + 1) % len(ring_nodes)
            self.add_edge(ring_nodes[i], ring_nodes[next_i])
        
        # Connetti nodi dell'anello agli hub
        for node in ring_nodes:
            # Ogni nodo dell'anello si connette a 1-2 hub
            num_hub_connections = random.randint(1, min(2, len(hubs)))
            connected_hubs = random.sample(hubs, num_hub_connections)
            for hub in connected_hubs:
                self.add_edge(node, hub)
        
        # Aggiungi alcune corde nell'anello per aumentare difficoltà
        num_chords = len(ring_nodes) // 3
        for _ in range(num_chords):
            i = random.randint(0, len(ring_nodes) - 1)
            j = random.randint(0, len(ring_nodes) - 1)
            if i != j and abs(i - j) > 1:
                self.add_edge(ring_nodes[i], ring_nodes[j])
        
        print(f"Generati {len(self.edges)} archi in struttura hub-ring")
    
    def generate_random_graph(self, edge_probability: float = 0.3):
        """
        Genera un grafo random secondo il modello Erdős–Rényi.
        
        Args:
            edge_probability: Probabilità di esistenza di ogni arco (0-1)
        """
        print(f"Generazione di grafo random con p={edge_probability}...")
        
        for i in range(1, self.num_nodes + 1):
            for j in range(i + 1, self.num_nodes + 1):
                if random.random() < edge_probability:
                    self.add_edge(i, j)
        
        print(f"Generati {len(self.edges)} archi in grafo random")
    
    def generate_planar_grid(self, add_diagonals: bool = False):
        """
        Genera un grafo a griglia (approssimativamente quadrata).
        
        Args:
            add_diagonals: Se True, aggiunge connessioni diagonali
        """
        # Calcola dimensioni della griglia
        rows = int(self.num_nodes ** 0.5)
        cols = (self.num_nodes + rows - 1) // rows
        
        print(f"Generazione di griglia {rows}x{cols}...")
        
        def node_id(r: int, c: int) -> int:
            return r * cols + c + 1
        
        for r in range(rows):
            for c in range(cols):
                current = node_id(r, c)
                if current > self.num_nodes:
                    break
                
                # Connessione a destra
                if c + 1 < cols and node_id(r, c + 1) <= self.num_nodes:
                    self.add_edge(current, node_id(r, c + 1))
                
                # Connessione in basso
                if r + 1 < rows and node_id(r + 1, c) <= self.num_nodes:
                    self.add_edge(current, node_id(r + 1, c))
                
                # Diagonali (se richieste)
                if add_diagonals:
                    if r + 1 < rows and c + 1 < cols and node_id(r + 1, c + 1) <= self.num_nodes:
                        self.add_edge(current, node_id(r + 1, c + 1))
                    if r + 1 < rows and c - 1 >= 0 and node_id(r + 1, c - 1) <= self.num_nodes:
                        self.add_edge(current, node_id(r + 1, c - 1))
        
        print(f"Generati {len(self.edges)} archi in griglia")
    
    def get_statistics(self) -> dict:
        """Calcola statistiche sul grafo generato."""
        degrees = {i: 0 for i in range(1, self.num_nodes + 1)}
        for u, v in self.edges:
            degrees[u] += 1
            degrees[v] += 1
        
        degree_values = list(degrees.values())
        avg_degree = sum(degree_values) / len(degree_values) if degree_values else 0
        max_degree = max(degree_values) if degree_values else 0
        min_degree = min(degree_values) if degree_values else 0
        
        return {
            'nodes': self.num_nodes,
            'edges': len(self.edges),
            'avg_degree': avg_degree,
            'max_degree': max_degree,
            'min_degree': min_degree,
            'density': (2 * len(self.edges)) / (self.num_nodes * (self.num_nodes - 1)) if self.num_nodes > 1 else 0
        }
    
    def write_to_file(self, filename: str, colors: List[str] = None):
        """
        Scrive il grafo in formato ASP nel file specificato.
        
        Args:
            filename: Nome del file di output
            colors: Lista di nomi dei colori (opzionale)
        """
        if colors is None:
            colors = ['red', 'green', 'blue', 'yellow', 'orange', 'purple', 'cyan', 'magenta'][:self.num_colors]
        
        with open(filename, 'w') as f:
            f.write("% --- Grafo Generato Automaticamente ---\n")
            f.write(f"% Parametri: {self.num_nodes} nodi, {self.num_colors} colori\n")
            
            stats = self.get_statistics()
            f.write(f"% Statistiche: {len(self.edges)} archi, ")
            f.write(f"grado medio {stats['avg_degree']:.2f}, ")
            f.write(f"densità {stats['density']:.3f}\n\n")
            
            # Nodi
            f.write(f"% Nodi del grafo\n")
            f.write(f"node(1..{self.num_nodes}).\n\n")
            
            # Archi (ordinati per leggibilità)
            f.write(f"% Archi del grafo ({len(self.edges)} archi)\n")
            sorted_edges = sorted(self.edges)
            for u, v in sorted_edges:
                f.write(f"edge({u},{v}).\n")
        
        print(f"\nGrafo scritto in '{filename}'")
        print(f"Statistiche:")
        for key, value in stats.items():
            if isinstance(value, float):
                print(f"  {key}: {value:.3f}")
            else:
                print(f"  {key}: {value}")


def main():
    """Funzione principale con interfaccia CLI."""
    parser = argparse.ArgumentParser(
        description='Genera istanze di Graph Coloring in modo procedurale',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Esempi di utilizzo:
  %(prog)s -n 50 -c 4 -t clusters -o graph_instance.lp
  %(prog)s -n 100 -c 5 -t hubs --num-hubs 10 -s 42
  %(prog)s -n 80 -c 4 -t random --edge-prob 0.25
  %(prog)s -n 64 -c 3 -t grid --diagonals
        """
    )
    
    # Parametri principali
    parser.add_argument('-n', '--nodes', type=int, default=30,
                        help='Numero di nodi nel grafo (default: 30)')
    parser.add_argument('-c', '--colors', type=int, default=5,
                        help='Numero di colori disponibili (default: 5)')
    parser.add_argument('-s', '--seed', type=int, default=None,
                        help='Seed per generazione random (per riproducibilità)')
    parser.add_argument('-o', '--output', type=str, default='graph_instance.lp',
                        help='File di output (default: graph_instance.lp)')
    
    # Tipo di grafo
    parser.add_argument('-t', '--type', type=str, default='clusters',
                        choices=['clusters', 'hubs', 'random', 'grid'],
                        help='Tipo di grafo da generare (default: clusters)')
    
    # Parametri specifici per tipo
    parser.add_argument('--num-clusters', type=int, default=5,
                        help='Numero di cluster (per tipo "clusters", default: 5)')
    parser.add_argument('--connectivity', type=float, default=0.7,
                        help='Connettività intra-cluster 0-1 (per tipo "clusters", default: 0.7)')
    parser.add_argument('--num-hubs', type=int, default=6,
                        help='Numero di nodi hub (per tipo "hubs", default: 6)')
    parser.add_argument('--edge-prob', type=float, default=0.3,
                        help='Probabilità di arco 0-1 (per tipo "random", default: 0.3)')
    parser.add_argument('--diagonals', action='store_true',
                        help='Aggiungi diagonali (per tipo "grid")')
    
    args = parser.parse_args()
    
    # Validazione
    if args.nodes < 1:
        parser.error("Il numero di nodi deve essere almeno 1")
    if args.colors < 1:
        parser.error("Il numero di colori deve essere almeno 1")
    if args.type == 'clusters' and args.num_clusters > args.nodes:
        parser.error("Il numero di cluster non può superare il numero di nodi")
    if args.type == 'hubs' and args.num_hubs >= args.nodes:
        parser.error("Il numero di hub deve essere minore del numero di nodi")
    
    print("="*60)
    print("  Generatore di Istanze Graph Coloring")
    print("="*60)
    print(f"\nParametri:")
    print(f"  Nodi: {args.nodes}")
    print(f"  Colori: {args.colors}")
    print(f"  Tipo: {args.type}")
    if args.seed is not None:
        print(f"  Seed: {args.seed}")
    print()
    
    # Crea il generatore
    generator = GraphGenerator(args.nodes, args.colors, args.seed)
    
    # Genera il grafo in base al tipo
    if args.type == 'clusters':
        generator.generate_clusters(args.num_clusters, args.connectivity)
    elif args.type == 'hubs':
        generator.generate_ring_with_hubs(args.num_hubs)
    elif args.type == 'random':
        generator.generate_random_graph(args.edge_prob)
    elif args.type == 'grid':
        generator.generate_planar_grid(args.diagonals)
    
    # Scrivi su file
    generator.write_to_file(args.output)
    
    print("\n" + "="*60)
    print("Grafo generato con successo!")
    print(f"Usa 'python no_heur.py' per testare la risoluzione")
    print("="*60)


if __name__ == "__main__":
    main()
