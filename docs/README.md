# Build di `clingo-modified`

Questi appunti servono per ricompilare la versione modificata di clingo che sta nella cartella `clingo-modified`.

## Idea generale

La build usa due strumenti:

- `cmake`: prepara la cartella di build. Legge i file `CMakeLists.txt`, controlla il compilatore, le opzioni e genera i file necessari per compilare.
- `ninja`: compila davvero i file C/C++ usando le istruzioni generate da CMake.

Quindi di solito ci sono due fasi diverse:

1. configurazione con `cmake`;
2. compilazione con `ninja`, oppure con lo script `recompile.sh`.

La configurazione si fa raramente: la prima volta, oppure quando vuoi cambiare opzioni importanti come `Debug`/`Release`.
La compilazione si fa ogni volta che modifichi il codice C++.

## Prima configurazione con CMake

Dalla root del repository, cioe' dalla cartella che contiene `clingo-modified`, esegui:

```bash
cmake -S clingo-modified -B clingo-modified/build -G Ninja -DCMAKE_BUILD_TYPE=Release
```

Significato delle opzioni:

- `-S clingo-modified`: indica a CMake dove sono i sorgenti, cioe' dove si trova il `CMakeLists.txt` principale.
- `-B clingo-modified/build`: indica dove creare la cartella di build. I file compilati finiscono qui, separati dai sorgenti.
- `-G Ninja`: dice a CMake di generare una build per Ninja.
- `-DCMAKE_BUILD_TYPE=Release`: compila in modalita' ottimizzata. E' quella da usare per benchmark e test di performance.

Se invece vuoi una build piu' comoda da debuggare, puoi usare:

```bash
cmake -S clingo-modified -B clingo-modified/build -G Ninja -DCMAKE_BUILD_TYPE=Debug
```

Pero' `Debug` e' piu' lenta e non usa le ottimizzazioni di `Release`.

## Ricompilare dopo una modifica

Dopo aver modificato un file `.cc` o `.hh`, normalmente non serve rilanciare tutto il comando CMake.
Usa lo script:

```bash
./test_folder/tools/recompile.sh
```

Lo script fa queste cose:

- trova automaticamente la root del repository;
- entra in `clingo-modified/build`;
- controlla se la build e' configurata in `Debug` e avvisa;
- esegue `ninja`.

In pratica e' una scorciatoia per:

```bash
cd clingo-modified/build
ninja
```

Il vantaggio di Ninja e' che ricompila solo quello che e' cambiato. Se modifichi un file, non ricompila tutto il progetto da zero: ricostruisce solo i pezzi necessari e poi rilinka gli eseguibili/librerie che dipendono da quel file.

## Comando alternativo senza entrare nella build directory

Se non vuoi usare direttamente `ninja`, puoi chiedere a CMake di chiamare lui il sistema di build configurato:

```bash
cmake --build clingo-modified/build -j2
```

Questo comando usa il generator scelto durante la configurazione. Nel nostro caso, siccome abbiamo configurato con `-G Ninja`, CMake chiamera' Ninja sotto il cofano.

`-j2` significa "usa 2 job in parallelo". Puoi aumentarlo se vuoi compilare piu' velocemente, ad esempio:

```bash
cmake --build clingo-modified/build -j8
```

## Dove finisce l'eseguibile

Dopo la compilazione, l'eseguibile modificato di clingo si trova qui:

```bash
clingo-modified/build/bin/clingo
```

Puoi controllare che esista con:

```bash
ls -l clingo-modified/build/bin/clingo
```

E puoi eseguirlo direttamente, ad esempio:

```bash
./clingo-modified/build/bin/clingo --version
```

## Quando rilanciare CMake

Usa solo `./test_folder/tools/recompile.sh` quando hai modificato codice normale, per esempio:

- file `.cc`;
- file `.hh`;
- piccoli cambi interni alla logica del propagatore.

Rilancia invece il comando `cmake -S ... -B ...` quando:

- la cartella `clingo-modified/build` non esiste;
- hai cambiato opzioni di build, per esempio da `Debug` a `Release`;
- hai modificato file `CMakeLists.txt`;
- CMake o Ninja si lamentano di una configurazione incoerente.

Per riconfigurare in `Release` una build gia' esistente:

```bash
cmake -S clingo-modified -B clingo-modified/build -G Ninja -DCMAKE_BUILD_TYPE=Release
```

Poi ricompila:

```bash
./test_folder/tools/recompile.sh
```
