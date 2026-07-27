#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Builds every diagram in this folder into png/<name>.png.
#
#   ./build.sh              # rebuild the diagrams whose source is newer
#   ./build.sh -f           # rebuild everything
#   ./build.sh pipelines    # rebuild a single diagram (with or without .tex)
#
# The thesis includes the PNGs, never the .tex sources, so a missing LaTeX
# toolchain on the machine that compiles the thesis is not a problem: the
# committed PNGs are enough.
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")"

DPI=${DPI:-600}
OUT=png
FORCE=0

args=()
for a in "$@"; do
    case "$a" in
        -f | --force) FORCE=1 ;;
        *) args+=("${a%.tex}") ;;
    esac
done

mkdir -p "$OUT"

if [[ ${#args[@]} -gt 0 ]]; then
    sources=("${args[@]/%/.tex}")
else
    sources=(*.tex)
fi

built=0
for src in "${sources[@]}"; do
    name="${src%.tex}"
    [[ "$name" == "common" ]] && continue
    [[ -f "$src" ]] || { echo "!! $src not found" >&2; exit 1; }

    png="$OUT/$name.png"
    if [[ $FORCE -eq 0 && -f "$png" && "$png" -nt "$src" && "$png" -nt common.tex ]]; then
        echo ".. $name up to date"
        continue
    fi

    echo ">> $name"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    pdflatex -interaction=nonstopmode -halt-on-error \
             -output-directory "$tmp" "$src" > "$tmp/log" 2>&1 \
        || { echo "!! pdflatex failed on $src, tail of the log:" >&2
             tail -n 25 "$tmp/log" >&2; exit 1; }

    # -singlefile keeps the name exactly as given, without the page suffix
    pdftoppm -png -r "$DPI" -singlefile "$tmp/$name.pdf" "$OUT/$name"

    rm -rf "$tmp"
    trap - EXIT
    built=$((built + 1))
done

echo "done ($built rebuilt) -> $PWD/$OUT"
