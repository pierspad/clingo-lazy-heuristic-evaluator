#!/usr/bin/env bash
# PUP benchmark iterator. The per-run execution and JSON stats parsing live in
# benchmark_runner.py.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
TEST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TEST_ROOT}/.." && pwd)"
RUNNER="${SCRIPT_DIR}/benchmark_runner.py"
CONVERTER="${TEST_ROOT}/tools/asp_heuristic_converter.py"

CLINGO_MOD="${CLINGO_MOD:-}"
for candidate in \
    "${REPO_ROOT}/build/bin/clingo" \
    "${REPO_ROOT}/clingo-modified/build/bin/clingo"; do
    if [ -z "${CLINGO_MOD}" ] && [ -x "${candidate}" ]; then
        CLINGO_MOD="${candidate}"
    fi
done

if [ -z "${CLINGO_MOD}" ]; then
    echo "Errore: binario clingo modificato non trovato."
    exit 1
fi

if [ ! -x "${RUNNER}" ]; then
    echo "Errore: runner benchmark non trovato: ${RUNNER}"
    exit 1
fi

if [ ! -f "${CONVERTER}" ]; then
    echo "Errore: convertitore non trovato: ${CONVERTER}"
    exit 1
fi

TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
MEM_LIMIT_BYTES="${MEM_LIMIT_BYTES:-$((32 * 1024 * 1024 * 1024))}"
REPEATS="${REPEATS:-2}"
STOP_VARIANT_ON_LIMIT="${STOP_VARIANT_ON_LIMIT:-1}"

ENC_DIR="${TEST_ROOT}/encodings/PUP"
INSTANCES_DOUBLE="${TEST_ROOT}/instances/PUP_instances/Double"
INSTANCES_DOUBLEV="${TEST_ROOT}/instances/PUP_instances/DoubleVariant"
RESULTS_DIR="${TEST_ROOT}/results"

FILE_PUP="${ENC_DIR}/PUP.lp"
FILE_PUP_HEUR="${ENC_DIR}/PUP_heur.lp"
FILE_PUP_DOUBLE_SRC="${ENC_DIR}/PUP_double.lp"
FILE_PUP_DOUBLEV_SRC="${ENC_DIR}/PUP_double_variant.lp"
FILE_PUP_DOUBLE_AUX="${ENC_DIR}/PUP_double_aux.lp"
FILE_PUP_DOUBLEV_AUX="${ENC_DIR}/PUP_double_variant_aux.lp"
FILE_PUP_DOUBLE="${ENC_DIR}/PUP_double_l.lp"
FILE_PUP_DOUBLEV="${ENC_DIR}/PUP_double_variant_l.lp"
FILE_PUP_DOUBLE_AUX_L="${ENC_DIR}/PUP_double_aux_l.lp"
FILE_PUP_DOUBLEV_AUX_L="${ENC_DIR}/PUP_double_variant_aux_l.lp"

extract_instance_size() {
    basename "$1" | grep -oE '[0-9]+' | tail -1
}

generate_lazy_encodings() {
    echo ""
    echo "Genero encoding derivati con ${CONVERTER}..."
    python3 "${CONVERTER}" "${FILE_PUP_DOUBLE_SRC}" --mode la -o "${FILE_PUP_DOUBLE}"
    python3 "${CONVERTER}" "${FILE_PUP_DOUBLEV_SRC}" --mode la -o "${FILE_PUP_DOUBLEV}"
    python3 "${CONVERTER}" "${FILE_PUP_DOUBLE_SRC}" --mode aux -o "${FILE_PUP_DOUBLE_AUX}"
    python3 "${CONVERTER}" "${FILE_PUP_DOUBLEV_SRC}" --mode aux -o "${FILE_PUP_DOUBLEV_AUX}"
    python3 "${CONVERTER}" "${FILE_PUP_DOUBLE_SRC}" --mode la-aux -o "${FILE_PUP_DOUBLE_AUX_L}"
    python3 "${CONVERTER}" "${FILE_PUP_DOUBLEV_SRC}" --mode la-aux -o "${FILE_PUP_DOUBLEV_AUX_L}"
}

run_encoding_on_instances() {
    local variant_name="$1"
    local encoding="$2"
    local instance_dir="$3"
    local csv_file="$4"
    local total_runs="$5"
    local current_run_ref="$6"
    local use_domain="$7"
    local semantics="$8"

    local -n _current_run="${current_run_ref}"
    local instances=()
    mapfile -t instances < <(find "${instance_dir}" -maxdepth 1 -type f -name "*.lp" | sort -V)

    if [ "${#instances[@]}" -eq 0 ]; then
        echo "  ATTENZIONE: nessuna istanza trovata in ${instance_dir}"
        return
    fi

    local limit_reached=0
    local limit_n=""

    for inst in "${instances[@]}"; do
        local instance_size
        instance_size="$(extract_instance_size "${inst}")"

        if [ "${STOP_VARIANT_ON_LIMIT:-1}" = "1" ] && [ "${limit_reached}" = "1" ]; then
            echo "--- ${variant_name}: salto N=${instance_size}; limite superato a N=${limit_n} ---"
            continue
        fi

        echo ""
        echo "  [${variant_name}] Istanza: $(basename "${inst}") (N=${instance_size})"

        for seed in $(seq 1 "${REPEATS}"); do
            _current_run=$((_current_run + 1))
            echo "--- ${variant_name} (run ${_current_run}/${total_runs}) ---"

            local cmd=(
                python3 "${RUNNER}"
                --clingo "${CLINGO_MOD}"
                --encoding "${encoding}"
                --instance "${inst}"
                --variant "${variant_name}"
                --semantics "${semantics}"
                --size "${instance_size}"
                --seed "${seed}"
                --csv "${csv_file}"
                --models 1
                --timeout "${TIMEOUT_SECONDS}"
                --memory-bytes "${MEM_LIMIT_BYTES}"
            )
            if [ "${use_domain}" = "yes" ]; then
                cmd+=(--domain-heuristic)
            fi
            
            if "${cmd[@]}"; then
                rc=0
            else
                rc=$?
            fi

            if [ "${rc}" -eq 75 -o "${rc}" -eq 124 ] && [ "${STOP_VARIANT_ON_LIMIT:-1}" = "1" ]; then
                limit_reached=1
                limit_n="${instance_size}"
                echo "--- ${variant_name}: limite memoria/timeout raggiunto a N=${instance_size}; salto i run e valori successivi ---"
                break
            fi
        done
    done
}

mkdir -p "${RESULTS_DIR}"
generate_lazy_encodings

n_double=$(find "${INSTANCES_DOUBLE}" -maxdepth 1 -type f -name "*.lp" | wc -l)
n_doublev=$(find "${INSTANCES_DOUBLEV}" -maxdepth 1 -type f -name "*.lp" | wc -l)
total_runs=$(( (n_double * 6 + n_doublev * 6) * REPEATS ))
current_run=0

CSV_DOUBLE="${RESULTS_DIR}/pup_double_results.csv"
CSV_DOUBLEV="${RESULTS_DIR}/pup_doublev_results.csv"
rm -f "${CSV_DOUBLE}" "${CSV_DOUBLEV}"

echo ""
echo "================================================================"
echo "  BENCHMARK PUP - Istanze Double"
echo "  Directory: ${INSTANCES_DOUBLE}"
echo "================================================================"

run_encoding_on_instances "pup"              "${FILE_PUP}"            "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run "no"  "native"
run_encoding_on_instances "pup_heur"         "${FILE_PUP_HEUR}"       "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run "yes" "native"
run_encoding_on_instances "pup_double_std"   "${FILE_PUP_DOUBLE_SRC}" "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run "yes" "native"
run_encoding_on_instances "pup_double_aux"   "${FILE_PUP_DOUBLE_AUX}" "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run "yes" "native"
run_encoding_on_instances "pup_double"       "${FILE_PUP_DOUBLE}"     "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run "yes" "alpha"
run_encoding_on_instances "pup_double_aux_l" "${FILE_PUP_DOUBLE_AUX_L}" "${INSTANCES_DOUBLE}" "${CSV_DOUBLE}" "${total_runs}" current_run "yes" "alpha"

echo ""
echo "================================================================"
echo "  BENCHMARK PUP - Istanze DoubleVariant"
echo "  Directory: ${INSTANCES_DOUBLEV}"
echo "================================================================"

run_encoding_on_instances "pup"               "${FILE_PUP}"             "${INSTANCES_DOUBLEV}" "${CSV_DOUBLEV}" "${total_runs}" current_run "no"  "native"
run_encoding_on_instances "pup_heur"          "${FILE_PUP_HEUR}"        "${INSTANCES_DOUBLEV}" "${CSV_DOUBLEV}" "${total_runs}" current_run "yes" "native"
run_encoding_on_instances "pup_doublev_std"   "${FILE_PUP_DOUBLEV_SRC}" "${INSTANCES_DOUBLEV}" "${CSV_DOUBLEV}" "${total_runs}" current_run "yes" "native"
run_encoding_on_instances "pup_doublev_aux"   "${FILE_PUP_DOUBLEV_AUX}" "${INSTANCES_DOUBLEV}" "${CSV_DOUBLEV}" "${total_runs}" current_run "yes" "native"
run_encoding_on_instances "pup_doublev"       "${FILE_PUP_DOUBLEV}"     "${INSTANCES_DOUBLEV}" "${CSV_DOUBLEV}" "${total_runs}" current_run "yes" "alpha"
run_encoding_on_instances "pup_doublev_aux_l" "${FILE_PUP_DOUBLEV_AUX_L}" "${INSTANCES_DOUBLEV}" "${CSV_DOUBLEV}" "${total_runs}" current_run "yes" "alpha"

echo ""
echo "================================================================"
echo "  Benchmark PUP completato. ${current_run} esecuzioni totali."
echo "  Risultati Double:        ${CSV_DOUBLE}"
echo "  Risultati DoubleVariant: ${CSV_DOUBLEV}"
echo "================================================================"
