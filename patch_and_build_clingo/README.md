# Patch and Build Clingo

Questa cartella contiene gli script per clonare, patchare e buildare custom version di `clingo`.

## Utilizzo

Per scaricare, patchare e compilare `clingo`, eseguire semplicemente:

```bash
./setup_clingo.sh
```

### Dettagli dei task automatizzati

1. **Clone**: Esegue una clonazione "shallow" della repository di clingo (dal repository ufficiale potassco/clingo).
2. **Sottomoduli**: Inizializza automaticamente i sottomoduli.
3. **Patch**: Applica al codice clonato il file `fix.patch` (necessario per risanare la compatibilità del lexer in re2c).
4. **Build**: Costruisce clingo attraverso CMake (in Debug, con Ninja e clang++).
