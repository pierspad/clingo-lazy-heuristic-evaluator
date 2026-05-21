#!/usr/bin/env bash
# BSP benchmark ridotto per studiare la sensibilita' alla randomizzazione della
# fase di search.
#
# Perche' esiste questo script
# ----------------------------
# Il benchmark BSP principale misura soprattutto il costo della rappresentazione
# lazy rispetto alla rappresentazione ground-and-solve: tempo totale, grounding,
# numero di regole, euristiche ground, memoria, scelte e conflitti.
#
# Questo script risponde a una domanda diversa: quanto e' stabile il comportamento
# della fase di solving quando Clingo riceve semi random diversi o quando gli
# consentiamo di fare una piccola percentuale di decisioni random?
#
# In altre parole, non serve a dimostrare che il grounding cambia con il seed:
# il grounding dovrebbe rimanere sostanzialmente invariato per stessa variante e
# stesso valore di n. Serve invece a vedere se la search percorre strade diverse.
# Se cambiano choices, conflicts e solving_s tra seed o tra setting, allora la
# differenza non e' solo rumore temporale della macchina: il solver sta davvero
# seguendo traiettorie di ricerca differenti.
#
# Parametri di default
# --------------------
#   BSP_VARIANTS = "la lc ga gc"
#       Confronta le due varianti lazy dirette e le due ground-and-solve piu'
#       rilevanti. Si tiene fuori il resto per mantenere il test piccolo e
#       leggibile.
#
#   REPEATS = 3
#       Esegue i seed 1, 2 e 3. Nel CSV ogni riga conserva il seed usato.
#
#   N_START=40, N_END=100, N_STEP=30
#       Usa tre dimensioni: 40, 70 e 100. Sono abbastanza distanti da mostrare
#       l'andamento senza trasformare questo esperimento in un benchmark enorme.
#
#   BSP_RANDOM_SETTINGS =
#       seed_only:
#           configurazione di controllo. Cambia solo --seed.
#
#       rand_freq_0_01:--rand-freq=0.01
#           configurazione randomizzata leggera. Circa l'1% delle decisioni puo'
#           essere casuale. E' abbastanza poco invasiva da restare spiegabile,
#           ma abbastanza forte da far emergere eventuale variabilita'.
#
# Output atteso
# -------------
# Lo script delega tutto a benchmark_bsp.sh, quindi produce il solito CSV:
#   test_folder/results/bsp_results.csv
#
# Le colonne importanti per questa analisi sono:
#   setting, seed, total_s, solving_s, choices, conflicts
#
# I grafici generati da generate_graphs.sh includono anche:
#   random_variability_seed_only.png
#   random_variability_rand_freq_0_01.png
#
# Come leggerli
# -------------
# - Se seed_only produce curve quasi identiche, significa che il solo seed non
#   influenza molto la configurazione standard.
# - Se rand_freq_0_01 separa le curve dei seed, significa che decisioni random
#   anche leggere cambiano il percorso di search.
# - Se rules, ground_lines o le metriche di grounding cambiano molto tra seed per
#   stessa variante/n/setting, il risultato e' sospetto: il seed dovrebbe
#   influenzare la search, non il grounding.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

export BSP_VARIANTS="${BSP_VARIANTS:-la lc ga gc}"
export REPEATS="${REPEATS:-3}"
export N_START="${N_START:-40}"
export N_END="${N_END:-100}"
export N_STEP="${N_STEP:-30}"
export BSP_RANDOM_SETTINGS="${BSP_RANDOM_SETTINGS:-seed_only: rand_freq_0_01:--rand-freq=0.01}"

exec "${SCRIPT_DIR}/benchmark_bsp.sh" "$@"
