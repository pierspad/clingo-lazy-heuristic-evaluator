#!/usr/bin/env bash
# Verifica che l'appiattimento uniforme dei livelli sia a COMPORTAMENTO INVARIATO.
#
# Confronta, per ogni encoding toccato dal refactor, il numero di Choices e
# Conflicts della versione nuova (working tree) contro quella vecchia (HEAD).
# Devono coincidere: l'appiattimento W_flat = W + P*M con M > max W intra-livello
# induce lo stesso ordine totale delle priorita' assolute alla Alpha.
#
# Uso:  ./verify_flattening_equivalence.sh
set -uo pipefail
cd "$(dirname "$0")"

NATIVE=clingo-native/build/bin/clingo
PROLOG=clingo-prolog/build/bin/clingo
FLAGS=(--stats=2 --heuristic=Domain -n 1)

HRP_INSTANCES=(test_folder/instances/HRP_instances/house-6.asp
               test_folder/instances/HRP_instances/house-10.asp)
PUP_INSTANCES=(test_folder/instances/PUP_instances/Double/double-20.asp
               test_folder/instances/PUP_instances/Double/double-40.asp)

OLD=$(mktemp -d); trap 'rm -rf "$OLD"' EXIT
fail=0

stats() { # $1 = binario, $2 = encoding, $3 = istanza, $4 = backend
    local env_prefix=()
    [[ $4 == prolog ]] && env_prefix=(env LAZY_HEURISTIC_BACKEND=prolog)
    timeout 300 "${env_prefix[@]}" "$1" "${FLAGS[@]}" "$2" "$3" 2>/dev/null |
        awk '/^Choices/{c=$3} /^Conflicts/{f=$3} END{printf "choices=%s conflicts=%s", c, f}'
}

compare() { # $1 = path relativo encoding, $2 = binario, $3 = backend, shift 3 = istanze
    local enc=$1 bin=$2 backend=$3; shift 3
    local old="$OLD/$(tr '/' '_' <<<"$enc")"
    git show "HEAD:$enc" > "$old" 2>/dev/null || { echo "SKIP  $enc (non in HEAD)"; return; }
    for inst in "$@"; do
        local n o
        n=$(stats "$bin" "$enc" "$inst" "$backend")
        o=$(stats "$bin" "$old" "$inst" "$backend")
        if [[ "$n" == "$o" && -n "$n" ]]; then
            printf 'OK    %-42s %-16s %s\n' "$(basename "$enc")" "$(basename "$inst")" "$n"
        else
            printf 'DIFF  %-42s %-16s new[%s] old[%s]\n' \
                   "$(basename "$enc")" "$(basename "$inst")" "$n" "$o"
            fail=1
        fi
    done
}

compare test_folder/encodings-native/3_HRP/HRP_la.lp "$NATIVE" native "${HRP_INSTANCES[@]}"
compare test_folder/encodings-native/3_HRP/HRP_lc.lp "$NATIVE" native "${HRP_INSTANCES[@]}"
compare test_folder/encodings-native/2_PUP/PUP_la.lp "$NATIVE" native "${PUP_INSTANCES[@]}"
compare test_folder/encodings-prolog/3_HRP/HRP_la.lp "$PROLOG" prolog "${HRP_INSTANCES[@]}"
compare test_folder/encodings-prolog/3_HRP/HRP_lc.lp "$PROLOG" prolog "${HRP_INSTANCES[@]}"
compare test_folder/encodings-prolog/2_PUP/PUP_la.lp "$PROLOG" prolog "${PUP_INSTANCES[@]}"
compare test_folder/encodings-prolog/2_PUP/PUP_lc.lp "$PROLOG" prolog "${PUP_INSTANCES[@]}"

echo
if (( fail )); then
    echo "ESITO: DIVERGENZE TROVATE -- il refactor NON e' a comportamento invariato."
else
    echo "ESITO: nessuna divergenza -- ordine di decisione identico, risultati della campagna validi."
fi
exit $fail
