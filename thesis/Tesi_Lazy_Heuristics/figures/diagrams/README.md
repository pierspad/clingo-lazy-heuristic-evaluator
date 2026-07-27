# Diagrammi della tesi

Diagrammi disegnati a mano in TikZ. Ogni `.tex` qui dentro è un documento
`standalone` indipendente: si apre, si modifica e si ricompila da solo, senza
toccare la tesi.

```
common.tex        stili e palette condivisi da tutti i diagrammi
pipelines.tex     ground-and-solve vs lazy sullo stesso euristico  (Sezione 1)
axes.tex          la matrice dei due assi e le quattro varianti    (Sezione 2)
architecture.tex  propagatore fra clasp e i due backend            (Sezione 2)
png/              output generato da build.sh -- è questo che la tesi include
```

## Ricompilare

```bash
./build.sh                 # rigenera solo i diagrammi il cui sorgente è cambiato
./build.sh -f              # rigenera tutto
./build.sh axes            # rigenera un diagramma solo
DPI=1200 ./build.sh -f     # risoluzione più alta (default 600)
```

La tesi include i PNG di `png/`, mai i sorgenti: chi compila la tesi non ha
bisogno di rigenerare nulla, bastano i PNG versionati.

## Modificarli a mano

Le posizioni sono coordinate esplicite in centimetri (`at (6.4,0)`), non
posizionamenti relativi a catena: spostare una scatola significa cambiare un
numero, senza che il resto del disegno si muova di conseguenza.

I colori e le forme non stanno nei singoli file ma in `common.tex`, negli stili
`ground` (blu, tutto ciò che è ground-and-solve), `lazy` (verde, tutto ciò che è
lazy), `neutral` (grigio, macchinari condivisi) e `alert` (rosso, l'artefatto
costoso). Cambiare la palette lì dentro si propaga a tutti i diagrammi.
