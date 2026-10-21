#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Il frontespizio originale resta intatto. Una firma digitale sul documento
# completo deve essere apposta solo dopo l'ultima build.
for tool in latexmk gs qpdf python3; do
    command -v "$tool" >/dev/null || { echo "Dipendenza mancante: $tool" >&2; exit 1; }
done
VERAPDF="${VERAPDF:-verapdf}"
if ! command -v "$VERAPDF" >/dev/null; then
    VERAPDF="$HOME/.local/share/verapdf/verapdf"
fi
[ -x "$(command -v "$VERAPDF" || true)" ] || {
    echo "Installa veraPDF oppure imposta VERAPDF al suo eseguibile." >&2; exit 1;
}
[ -f frontespizio_firmato.pdf ] || { echo "Manca frontespizio_firmato.pdf" >&2; exit 1; }
[ "$(qpdf --show-npages frontespizio_firmato.pdf)" = 1 ] || {
    echo "Il frontespizio firmato deve contenere esattamente una pagina." >&2; exit 1;
}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "=== 1. Compilazione LaTeX (latexmk + minted + biber) ==="
latexmk -pdf -shell-escape -interaction=nonstopmode -halt-on-error Spadafora_Pierpaolo_Thesis.tex

echo "=== 2. Sostituzione della prima pagina con il frontespizio firmato ==="
qpdf Spadafora_Pierpaolo_Thesis.pdf --pages frontespizio_firmato.pdf 1 \
    Spadafora_Pierpaolo_Thesis.pdf 2-z -- "$WORK/tesi-con-frontespizio.pdf" || {
    status=$?
    # qpdf usa 3 per operazioni riuscite con avvisi; gli errori restano fatali.
    [ "$status" -eq 3 ] || exit "$status"
}

echo "=== 3. Conversione in PDF/A-2b con Ghostscript ==="
ICC_PROFILE="/usr/share/ghostscript/iccprofiles/srgb.icc"
if [ ! -f "$ICC_PROFILE" ]; then
    # Fallback su altri percorsi noti se srgb.icc non è nel percorso predefinito
    ICC_PROFILE=$(find /usr/share/ghostscript /usr/share/color/icc -type f \( -name "srgb.icc" -o -name "sRGB.icc" \) -print -quit 2>/dev/null || true)
fi

[ -f "$ICC_PROFILE" ] || { echo "Profilo ICC sRGB non trovato" >&2; exit 1; }
PDFA_DEF="$WORK/pdfa.ps"

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
   -sDEVICE=pdfwrite -dPDFACompatibilityPolicy=2 \
   --permit-file-read="$ICC_PROFILE" \
   -sOutputFile="$WORK/tesi-pdfa.pdf" \
   "$PDFA_DEF" "$WORK/tesi-con-frontespizio.pdf"

echo "=== 4. Validazione PDF/A-2b con veraPDF ==="
"$VERAPDF" --format xml --flavour 2b "$WORK/tesi-pdfa.pdf" > "$WORK/validation.xml"
python3 - "$WORK/validation.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
reports = [e for e in root.iter() if e.tag.split('}')[-1] == 'validationReport']
if len(reports) != 1 or reports[0].get('isCompliant') != 'true':
    print(open(sys.argv[1]).read(), file=sys.stderr)
    sys.exit('Validazione PDF/A-2b fallita: il PDF finale precedente è conservato.')
print('Conformità PDF/A-2b verificata.')
PYXML
[ "$(qpdf --show-npages "$WORK/tesi-pdfa.pdf")" = \
  "$(qpdf --show-npages Spadafora_Pierpaolo_Thesis.pdf)" ] || {
    echo "Numero di pagine inatteso" >&2; exit 1;
}
cp "$WORK/validation.xml" Spadafora_Pierpaolo_Thesis_PDFA.validation.xml
mv "$WORK/tesi-pdfa.pdf" Spadafora_Pierpaolo_Thesis_PDFA.pdf

echo "=== 5. Completato con successo! ==="
echo "File generato: Spadafora_Pierpaolo_Thesis_PDFA.pdf"
ls -lh "Spadafora_Pierpaolo_Thesis_PDFA.pdf"

# Pulizia soltanto dopo compilazione e conversione riuscite.
latexmk -c Spadafora_Pierpaolo_Thesis.tex
rm -f -- ./*.aux ./*.bcf ./*.blg ./*.bbl ./*.fdb_latexmk ./*.fls ./*.log ./*.out ./*.run.xml ./*.toc
rm -rf -- _minted _minted-Spadafora_Pierpaolo_Thesis
echo "Pulizia completata; sorgenti, frontespizio firmato e PDF conservati."
