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
#   DEFAULT_BSP_VARIANTS = "la lc ga gc"
#       Confronta le due varianti lazy dirette e le due ground-and-solve piu'
#       rilevanti. Si tiene fuori il resto per mantenere il test piccolo e
#       leggibile.
#
#   DEFAULT_REPEATS = 3
#       Esegue i seed 1, 2 e 3. Nel CSV ogni riga conserva il seed usato.
#
#   DEFAULT_N_START=40, DEFAULT_N_END=100, DEFAULT_N_STEP=30
#       Usa tre dimensioni: 40, 70 e 100. Sono abbastanza distanti da mostrare
#       l'andamento senza trasformare questo esperimento in un benchmark enorme.
#
#   DEFAULT_BSP_RANDOM_SETTINGS =
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
# Script opzionale: non e' il benchmark BSP principale. Delega tutto a
# benchmark_bsp.sh, ma usa file dedicati per non sovrascrivere il benchmark BSP
# completo:
#   test_folder/results/bsp_random_results.csv
#   test_folder/results/run_random_metadata.json
#   test_folder/results/bsp_random_failures.txt
#
# Le colonne importanti per questa analisi sono:
#   setting, seed, total_s, solving_s, choices, conflicts
#
# I grafici generati da generate_graphs.sh includono anche:
#   test_folder/results/graphs/bsp_random/standard/random_variability_seed_only.png
#   test_folder/results/graphs/bsp_random/standard/random_variability_rand_freq_0_01.png
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
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ==============================================================================
# PARAMETRI MODIFICABILI
#
# Cambia questi valori per definire la matrice randomizzata di default.
# Puoi ancora sovrascriverli da shell, per esempio:
#   DEFAULT_REPEATS=5 ./benchmark_bsp_random.sh
#   BSP_VARIANTS="la gc" ./benchmark_bsp_random.sh
# ==============================================================================
DEFAULT_BSP_VARIANTS="${DEFAULT_BSP_VARIANTS:-la lc ga gc}"
DEFAULT_REPEATS="${DEFAULT_REPEATS:-3}"
DEFAULT_N_START="${DEFAULT_N_START:-40}"
DEFAULT_N_END="${DEFAULT_N_END:-100}"
DEFAULT_N_STEP="${DEFAULT_N_STEP:-30}"
DEFAULT_BSP_RANDOM_SETTINGS="${DEFAULT_BSP_RANDOM_SETTINGS:-seed_only: rand_freq_0_01:--rand-freq=0.01}"
DEFAULT_RANDOM_CSV="${DEFAULT_RANDOM_CSV:-${TEST_ROOT}/results/bsp_random_results.csv}"
DEFAULT_RANDOM_METADATA="${DEFAULT_RANDOM_METADATA:-${TEST_ROOT}/results/run_random_metadata.json}"
DEFAULT_RANDOM_FAILURES="${DEFAULT_RANDOM_FAILURES:-${TEST_ROOT}/results/bsp_random_failures.txt}"
# ==============================================================================

export BSP_VARIANTS="${BSP_VARIANTS:-${DEFAULT_BSP_VARIANTS}}"
export REPEATS="${REPEATS:-${DEFAULT_REPEATS}}"
export N_START="${N_START:-${DEFAULT_N_START}}"
export N_END="${N_END:-${DEFAULT_N_END}}"
export N_STEP="${N_STEP:-${DEFAULT_N_STEP}}"
export BSP_RANDOM_SETTINGS="${BSP_RANDOM_SETTINGS:-${DEFAULT_BSP_RANDOM_SETTINGS}}"
export BSP_RESULTS_CSV="${BSP_RESULTS_CSV:-${DEFAULT_RANDOM_CSV}}"
export BSP_METADATA_FILE="${BSP_METADATA_FILE:-${DEFAULT_RANDOM_METADATA}}"
export BSP_FAILURES_FILE="${BSP_FAILURES_FILE:-${DEFAULT_RANDOM_FAILURES}}"

exec "${SCRIPT_DIR}/benchmark_bsp.sh" "$@"
