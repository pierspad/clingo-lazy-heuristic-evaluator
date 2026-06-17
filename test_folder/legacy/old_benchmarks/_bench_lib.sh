#!/usr/bin/env bash
# ============================================================
# Libreria condivisa dei benchmark per-backend.
# Usata dai wrapper: 1_native_bsp.sh, 1_prolog_bsp.sh,
#                    2_native_pup.sh, 2_prolog_pup.sh,
#                    3_native_hrp.sh, 3_prolog_hrp.sh,
#                    2_benchmark_bsp_random.sh
#
# Ogni wrapper definisce BACKEND ("native"|"prolog") e poi chiama
# run_bsp / run_pup / run_hrp / run_bsp_random. La libreria individua il binario
# clingo del backend, la cartella di encoding corrispondente, e itera
# (seed x variante x istanza) chiamando benchmark_runner.py, che appende
# una riga al CSV.
#
# LAYOUT DEI RISULTATI (uno per backend):
#   results-native/1_BSP_native.csv   results-native/2_PUP_native.csv   results-native/3_HRP_native.csv
#   results-prolog/1_BSP_prolog.csv   results-prolog/2_PUP_prolog.csv   results-prolog/3_HRP_prolog.csv
#   results-<backend>/1_BSP_<backend>_random.csv   (run multi-seed/randomici)
#
# WIRING DEL BACKEND PROLOG (correzione critica):
#   Il binario clingo-prolog usa il motore SWI-Prolog in-process per
#   valutare le euristiche query-driven SOLO se e' settato
#   LAZY_HEURISTIC_BACKEND=prolog. Senza quella variabile gli encoding
#   prolog (heuristic("... aggregate_all/holds/is ...")) ricadono sul
#   backend ausiliario, che non conosce quella sintassi: la regola
#   fallisce in silenzio (unknown=fail) e la ricerca gira SENZA euristica
#   (le scelte coincidono con gc_noheur). Per questo run_bsp/run_pup
#   esportano LAZY_HEURISTIC_BACKEND=prolog quando backend=prolog.
#
# Override via ambiente: CLINGO_BIN, TIMEOUT, MODELS, VARIANTS, SEEDS,
#   (BSP) N_START N_END N_STEP, (PUP) PUP_GLOB, (HRP) HRP_GLOB,
#   (random) RANDOM_SETTINGS, RANDOM_CSV.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TEST_ROOT}/.." && pwd)"
RUNNER="${SCRIPT_DIR}/benchmark_runner.py"
PYTHON_BIN="${PYTHON_BIN:-python3}"

# Cartella risultati per-backend: results-native / results-prolog.
results_dir_for() {
    echo "${TEST_ROOT}/results-$1"
}

# Binario clingo per backend (native = C++ puro, prolog = backend SWI-Prolog).
resolve_clingo() {
    local backend="$1"
    if [ -n "${CLINGO_BIN:-}" ]; then echo "${CLINGO_BIN}"; return; fi
    echo "${REPO_ROOT}/clingo-${backend}/build/bin/clingo"
}

# Attiva il motore SWI-Prolog in-process per il backend prolog; per il
# backend native la variabile e' irrilevante (il binario non la legge) ma
# la disattiviamo comunque per pulizia.
configure_backend_env() {
    local backend="$1"
    if [ "${backend}" = "prolog" ]; then
        export LAZY_HEURISTIC_BACKEND=prolog
    else
        unset LAZY_HEURISTIC_BACKEND
    fi
}

# Semantica per variante (etichetta CSV; la negazione/aggregati reali
# sono gia' codificati nell'encoding).
variant_semantics() {
    case "$1" in
        gc|gc_noheur|lc) echo "clingo" ;;
        ga|ga_weak|la|la_aux|la_co) echo "alpha" ;;
        *) echo "native" ;;
    esac
}

# Espande SEEDS in un array. "" / "none" => nessun --seed (default clingo).
read_seeds() {
    local raw="${SEEDS:-none}"
    SEEDS_ARRAY=()
    if [ "${raw}" = "none" ] || [ -z "${raw}" ]; then
        SEEDS_ARRAY=("none")
    else
        read -r -a SEEDS_ARRAY <<< "${raw}"
    fi
}

# Costruisce SEED_ARGS per il runner. seed "none" => nessun --seed.
seed_args() {
    local seed="$1"
    SEED_ARGS=()
    if [ "${seed}" != "none" ]; then
        SEED_ARGS=(--seed "${seed}")
    fi
}

# ---------- BSP: la taglia e' la costante n (range) ----------
run_bsp() {
    local backend="$1"
    local clingo enc_dir range csv results_dir
    clingo="$(resolve_clingo "${backend}")"
    enc_dir="${TEST_ROOT}/encodings-${backend}/1_BSP"
    range="${TEST_ROOT}/instances/BSP_instances/BSP_range.lp"
    results_dir="$(results_dir_for "${backend}")"
    csv="${results_dir}/1_BSP_${backend}.csv"

    local -a variants
    read -r -a variants <<< "${VARIANTS:-ga_weak ga gc_noheur gc la_aux la_co la lc}"
    read_seeds
    local n_start="${N_START:-3}" n_end="${N_END:-30}" n_step="${N_STEP:-1}"
    local timeout="${TIMEOUT:-60}" models="${MODELS:-1}"

    preflight "${clingo}" "${enc_dir}" "${csv}"
    configure_backend_env "${backend}"
    mkdir -p "${results_dir}"
    echo ">> BSP backend=${backend} clingo=${clingo}"
    echo ">> encodings=${enc_dir}  n=${n_start}..${n_end} step=${n_step}  seeds=${SEEDS_ARRAY[*]}"
    echo ">> csv=${csv}  LAZY_HEURISTIC_BACKEND=${LAZY_HEURISTIC_BACKEND:-<unset>}"

    local n v f seed
    for ((n = n_start; n <= n_end; n += n_step)); do
        for v in "${variants[@]}"; do
            f="${enc_dir}/BSP_${v}.lp"
            [ -f "${f}" ] || { echo "   skip ${v} (manca ${f})"; continue; }
            for seed in "${SEEDS_ARRAY[@]}"; do
                seed_args "${seed}"
                echo "   [n=${n} seed=${seed}] BSP_${v}"
                "${PYTHON_BIN}" "${RUNNER}" \
                    --clingo "${clingo}" \
                    --encoding "${f}" --instance "${range}" \
                    --variant "${v}" --semantics "$(variant_semantics "${v}")" \
                    --setting "${backend}" --size "${n}" -c "n=${n}" \
                    "${SEED_ARGS[@]}" \
                    --domain-heuristic --models "${models}" --timeout "${timeout}" \
                    --ground-timeout "${GROUND_TIMEOUT:-300}" \
                    --csv "${csv}" || echo "   ! run fallito (${v}, n=${n}, seed=${seed})"
            done
        done
    done
    echo ">> fatto. risultati in ${csv}"
}

# ---------- PUP: le istanze sono file double-*.asp ----------
run_pup() {
    local backend="$1"
    local clingo enc_dir csv results_dir
    clingo="$(resolve_clingo "${backend}")"
    enc_dir="${TEST_ROOT}/encodings-${backend}/2_PUP"
    results_dir="$(results_dir_for "${backend}")"
    csv="${results_dir}/2_PUP_${backend}.csv"

    local -a variants
    read -r -a variants <<< "${VARIANTS:-gc_noheur gc ga la lc}"
    read_seeds
    local glob="${PUP_GLOB:-${TEST_ROOT}/instances/PUP_instances/Double/double-*.asp}"
    local timeout="${TIMEOUT:-180}" models="${MODELS:-1}"

    preflight "${clingo}" "${enc_dir}" "${csv}"
    configure_backend_env "${backend}"
    mkdir -p "${results_dir}"
    echo ">> PUP backend=${backend} clingo=${clingo}"
    echo ">> encodings=${enc_dir}  istanze=${glob}  seeds=${SEEDS_ARRAY[*]}"
    echo ">> csv=${csv}  LAZY_HEURISTIC_BACKEND=${LAZY_HEURISTIC_BACKEND:-<unset>}"

    local inst size v f seed
    for inst in ${glob}; do
        [ -f "${inst}" ] || continue
        size="$(basename "${inst}" | sed -E 's/[^0-9]*([0-9]+).*/\1/')"
        for v in "${variants[@]}"; do
            f="${enc_dir}/PUP_${v}.lp"
            [ -f "${f}" ] || { echo "   skip ${v} (manca ${f})"; continue; }
            for seed in "${SEEDS_ARRAY[@]}"; do
                seed_args "${seed}"
                echo "   [n=${size} seed=${seed}] PUP_${v}  ($(basename "${inst}"))"
                "${PYTHON_BIN}" "${RUNNER}" \
                    --clingo "${clingo}" \
                    --encoding "${f}" --instance "${inst}" \
                    --variant "${v}" --semantics "$(variant_semantics "${v}")" \
                    --setting "${backend}" --size "${size}" \
                    "${SEED_ARGS[@]}" \
                    --domain-heuristic --models "${models}" --timeout "${timeout}" \
                    --ground-timeout "${GROUND_TIMEOUT:-300}" \
                    --csv "${csv}" || echo "   ! run fallito (${v}, ${inst}, seed=${seed})"
            done
        done
    done
    echo ">> fatto. risultati in ${csv}"
}

# ---------- HRP: le istanze sono file house-*.asp ----------
run_hrp() {
    local backend="$1"
    local clingo enc_dir csv results_dir
    clingo="$(resolve_clingo "${backend}")"
    enc_dir="${TEST_ROOT}/encodings-${backend}/3_HRP"
    results_dir="$(results_dir_for "${backend}")"
    csv="${results_dir}/3_HRP_${backend}.csv"

    local -a variants
    read -r -a variants <<< "${VARIANTS:-gc_noheur gc ga la lc}"
    read_seeds
    local glob="${HRP_GLOB:-${TEST_ROOT}/instances/HRP_instances/house-*.asp}"
    local timeout="${TIMEOUT:-180}" models="${MODELS:-1}"

    preflight "${clingo}" "${enc_dir}" "${csv}"
    configure_backend_env "${backend}"
    mkdir -p "${results_dir}"
    echo ">> HRP backend=${backend} clingo=${clingo}"
    echo ">> encodings=${enc_dir}  istanze=${glob}  seeds=${SEEDS_ARRAY[*]}"
    echo ">> csv=${csv}  LAZY_HEURISTIC_BACKEND=${LAZY_HEURISTIC_BACKEND:-<unset>}"

    local inst size v f seed
    for inst in ${glob}; do
        [ -f "${inst}" ] || continue
        size="$(basename "${inst}" | sed -E 's/[^0-9]*([0-9]+).*/\1/')"
        for v in "${variants[@]}"; do
            f="${enc_dir}/HRP_${v}.lp"
            [ -f "${f}" ] || { echo "   skip ${v} (manca ${f})"; continue; }
            for seed in "${SEEDS_ARRAY[@]}"; do
                seed_args "${seed}"
                echo "   [n=${size} seed=${seed}] HRP_${v}  ($(basename "${inst}"))"
                "${PYTHON_BIN}" "${RUNNER}" \
                    --clingo "${clingo}" \
                    --encoding "${f}" --instance "${inst}" \
                    --variant "${v}" --semantics "$(variant_semantics "${v}")" \
                    --setting "${backend}" --size "${size}" \
                    "${SEED_ARGS[@]}" \
                    --domain-heuristic --models "${models}" --timeout "${timeout}" \
                    --ground-timeout "${GROUND_TIMEOUT:-300}" \
                    --csv "${csv}" || echo "   ! run fallito (${v}, ${inst}, seed=${seed})"
            done
        done
    done
    echo ">> fatto. risultati in ${csv}"
}

# ---------- BSP randomico / multi-seed (analisi di varianza) ----------
# Confronta la sensibilita' di clasp a seed e opzioni randomizzate.
# Ogni "setting" e' una coppia nome:opzione-clingo (vuota = solo seed).
# La colonna CSV `setting` riceve il NOME del setting (non il backend), cosi'
# gen_graphs.py --type bsp_random puo' raggruppare le curve per setting.
run_bsp_random() {
    local backend="$1"
    local clingo enc_dir range csv results_dir
    clingo="$(resolve_clingo "${backend}")"
    enc_dir="${TEST_ROOT}/encodings-${backend}/1_BSP"
    range="${TEST_ROOT}/instances/BSP_instances/BSP_range.lp"
    results_dir="$(results_dir_for "${backend}")"
    csv="${RANDOM_CSV:-${results_dir}/1_BSP_${backend}_random.csv}"

    local -a variants
    read -r -a variants <<< "${VARIANTS:-la lc ga gc}"
    # Per la varianza servono piu' seed.
    SEEDS="${SEEDS:-1 2 3}"
    read_seeds
    local -a settings
    read -r -a settings <<< "${RANDOM_SETTINGS:-seed_only: rand_freq_0_01:--rand-freq=0.01}"
    local n_start="${N_START:-40}" n_end="${N_END:-100}" n_step="${N_STEP:-30}"
    local timeout="${TIMEOUT:-120}" models="${MODELS:-1}"

    preflight "${clingo}" "${enc_dir}" "${csv}"
    configure_backend_env "${backend}"
    mkdir -p "${results_dir}"
    echo ">> BSP-random backend=${backend} clingo=${clingo}"
    echo ">> n=${n_start}..${n_end} step=${n_step}  seeds=${SEEDS_ARRAY[*]}  settings=${settings[*]}"
    echo ">> csv=${csv}  LAZY_HEURISTIC_BACKEND=${LAZY_HEURISTIC_BACKEND:-<unset>}"

    local n v f seed setting setting_name setting_opt
    for ((n = n_start; n <= n_end; n += n_step)); do
        for v in "${variants[@]}"; do
            f="${enc_dir}/BSP_${v}.lp"
            [ -f "${f}" ] || { echo "   skip ${v} (manca ${f})"; continue; }
            for setting in "${settings[@]}"; do
                setting_name="${setting%%:*}"
                setting_opt="${setting#*:}"
                local -a opt_args=()
                [ -n "${setting_opt}" ] && opt_args=(--clingo-option "${setting_opt}")
                for seed in "${SEEDS_ARRAY[@]}"; do
                    seed_args "${seed}"
                    echo "   [n=${n} seed=${seed} setting=${setting_name}] BSP_${v}"
                    "${PYTHON_BIN}" "${RUNNER}" \
                        --clingo "${clingo}" \
                        --encoding "${f}" --instance "${range}" \
                        --variant "${v}" --semantics "$(variant_semantics "${v}")" \
                        --setting "${setting_name}" --size "${n}" -c "n=${n}" \
                        "${SEED_ARGS[@]}" "${opt_args[@]}" \
                        --domain-heuristic --models "${models}" --timeout "${timeout}" \
                    --ground-timeout "${GROUND_TIMEOUT:-300}" \
                        --csv "${csv}" || echo "   ! run fallito (${v}, n=${n}, seed=${seed}, ${setting_name})"
                done
            done
        done
    done
    echo ">> fatto. risultati in ${csv}"
}

preflight() {
    local clingo="$1" enc_dir="$2" csv="${3:-}"
    if [ ! -x "${clingo}" ]; then
        echo "Errore: binario clingo non trovato/eseguibile: ${clingo}" >&2
        echo "Suggerimento: compila il backend (vedi tools/recompile.sh) o esporta CLINGO_BIN." >&2
        exit 1
    fi
    if [ ! -d "${enc_dir}" ]; then
        echo "Errore: cartella encoding mancante: ${enc_dir}" >&2
        exit 1
    fi
    if [ ! -f "${RUNNER}" ]; then
        echo "Errore: runner non trovato: ${RUNNER}" >&2
        exit 1
    fi
}
