#!/usr/bin/env bash
# ============================================================
# Libreria condivisa dei benchmark per-backend.
# Usata dai wrapper: 1_native_bsp.sh, 1_prolog_bsp.sh,
#                    2_native_pup.sh, 2_prolog_pup.sh
#
# Ogni wrapper definisce BACKEND ("native"|"prolog") e poi chiama
# run_bsp oppure run_pup. La libreria individua il binario clingo del
# backend, la cartella di encoding corrispondente, e itera variante x
# istanza chiamando benchmark_runner.py (che appende una riga al CSV).
#
# Override via ambiente: CLINGO_BIN, TIMEOUT, MODELS, VARIANTS,
#   (BSP) N_START N_END N_STEP, (PUP) PUP_GLOB.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TEST_ROOT}/.." && pwd)"
RUNNER="${SCRIPT_DIR}/benchmark_runner.py"
PYTHON_BIN="${PYTHON_BIN:-python3}"
RESULTS_DIR="${TEST_ROOT}/results"

# Binario clingo per backend (native = C++ puro, prolog = backend SWI-Prolog).
resolve_clingo() {
    local backend="$1"
    if [ -n "${CLINGO_BIN:-}" ]; then echo "${CLINGO_BIN}"; return; fi
    echo "${REPO_ROOT}/clingo-${backend}/build/bin/clingo"
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

# ---------- BSP: la taglia e' la costante n (range) ----------
run_bsp() {
    local backend="$1"
    local clingo enc_dir range csv
    clingo="$(resolve_clingo "${backend}")"
    enc_dir="${TEST_ROOT}/encodings-${backend}/1_BSP"
    range="${TEST_ROOT}/instances/BSP_instances/BSP_range.lp"
    csv="${RESULTS_DIR}/bsp_${backend}_results.csv"

    local -a variants
    read -r -a variants <<< "${VARIANTS:-ga_weak ga gc_noheur gc la_aux la_co la lc}"
    local n_start="${N_START:-3}" n_end="${N_END:-30}" n_step="${N_STEP:-1}"
    local timeout="${TIMEOUT:-60}" models="${MODELS:-1}"

    preflight "${clingo}" "${enc_dir}"
    mkdir -p "${RESULTS_DIR}"
    echo ">> BSP backend=${backend} clingo=${clingo}"
    echo ">> encodings=${enc_dir}  n=${n_start}..${n_end} step=${n_step}  csv=${csv}"

    local n v f
    for ((n = n_start; n <= n_end; n += n_step)); do
        for v in "${variants[@]}"; do
            f="${enc_dir}/BSP_${v}.lp"
            [ -f "${f}" ] || { echo "   skip ${v} (manca ${f})"; continue; }
            echo "   [n=${n}] BSP_${v}"
            "${PYTHON_BIN}" "${RUNNER}" \
                --clingo "${clingo}" \
                --encoding "${f}" --instance "${range}" \
                --variant "${v}" --semantics "$(variant_semantics "${v}")" \
                --setting "${backend}" --size "${n}" -c "n=${n}" \
                --domain-heuristic --models "${models}" --timeout "${timeout}" \
                --csv "${csv}" || echo "   ! run fallito (${v}, n=${n})"
        done
    done
    echo ">> fatto. risultati in ${csv}"
}

# ---------- PUP: le istanze sono file double-*.asp ----------
run_pup() {
    local backend="$1"
    local clingo enc_dir csv
    clingo="$(resolve_clingo "${backend}")"
    enc_dir="${TEST_ROOT}/encodings-${backend}/2_PUP"
    csv="${RESULTS_DIR}/pup_${backend}_results.csv"

    local -a variants
    read -r -a variants <<< "${VARIANTS:-gc_noheur gc ga la lc}"
    local glob="${PUP_GLOB:-${TEST_ROOT}/instances/PUP_instances/Double/double-*.asp}"
    local timeout="${TIMEOUT:-180}" models="${MODELS:-1}"

    preflight "${clingo}" "${enc_dir}"
    mkdir -p "${RESULTS_DIR}"
    echo ">> PUP backend=${backend} clingo=${clingo}"
    echo ">> encodings=${enc_dir}  istanze=${glob}  csv=${csv}"

    local inst size v f
    for inst in ${glob}; do
        [ -f "${inst}" ] || continue
        size="$(basename "${inst}" | sed -E 's/[^0-9]*([0-9]+).*/\1/')"
        for v in "${variants[@]}"; do
            f="${enc_dir}/PUP_${v}.lp"
            [ -f "${f}" ] || { echo "   skip ${v} (manca ${f})"; continue; }
            echo "   [n=${size}] PUP_${v}  ($(basename "${inst}"))"
            "${PYTHON_BIN}" "${RUNNER}" \
                --clingo "${clingo}" \
                --encoding "${f}" --instance "${inst}" \
                --variant "${v}" --semantics "$(variant_semantics "${v}")" \
                --setting "${backend}" --size "${size}" \
                --domain-heuristic --models "${models}" --timeout "${timeout}" \
                --csv "${csv}" || echo "   ! run fallito (${v}, ${inst})"
        done
    done
    echo ">> fatto. risultati in ${csv}"
}

preflight() {
    local clingo="$1" enc_dir="$2"
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
