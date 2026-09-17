#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=== 1. Compilazione LaTeX (latexmk + minted + biber) ==="
latexmk -pdf -shell-escape -interaction=nonstopmode Spadafora_Pierpaolo_Thesis.tex

echo "=== 2. Conversione in PDF/A-2b con Ghostscript ==="
ICC_PROFILE="/usr/share/ghostscript/iccprofiles/srgb.icc"
if [ ! -f "$ICC_PROFILE" ]; then
    # Fallback su altri percorsi noti se srgb.icc non è nel percorso predefinito
    ICC_PROFILE=$(find /usr/share/ghostscript /usr/share/color/icc -name "srgb.icc" -o -name "sRGB.icc" 2>/dev/null | head -n 1)
fi

PDFA_DEF=$(mktemp --suffix=.ps)
trap 'rm -f "$PDFA_DEF"' EXIT

cat << EOF > "$PDFA_DEF"
%!
[ /Title (Lazy Declarative Heuristics in Answer Set Programming)
  /Author (Pierpaolo Spadafora)
  /Subject (Design and evaluation of a lazy heuristic propagator for clingo)
  /Keywords (Answer Set Programming, clingo, lazy heuristics, domain-specific heuristics)
  /DOCINFO pdfmark

/ICCProfile ($ICC_PROFILE) def
[/_objdef {icc_PDFA} /type /stream /OBJ pdfmark
[{icc_PDFA} << /N 3 >> /PUT pdfmark
[{icc_PDFA} ICCProfile (r) file /PUT pdfmark
[ {Catalog} << /OutputIntents [ <<
  /Type /OutputIntent
  /S /GTS_PDFA1
  /OutputConditionIdentifier (sRGB)
  /Info (sRGB)
  /DestOutputProfile {icc_PDFA}
>> ] >> /PUT pdfmark
EOF

gs -dPDFA=2 -dBATCH -dNOPAUSE -sProcessColorModel=DeviceRGB -sColorConversionStrategy=RGB \
   -sDEVICE=pdfwrite -dPDFACompatibilityPolicy=1 \
   --permit-file-read="$ICC_PROFILE" \
   -sOutputFile="Spadafora_Pierpaolo_Thesis_PDFA.pdf" \
   "$PDFA_DEF" "Spadafora_Pierpaolo_Thesis.pdf"

echo "=== 3. Completato con successo! ==="
echo "File generato: Spadafora_Pierpaolo_Thesis_PDFA.pdf"
ls -lh "Spadafora_Pierpaolo_Thesis_PDFA.pdf"
