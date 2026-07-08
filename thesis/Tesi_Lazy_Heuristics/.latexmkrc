# 1. Forza la pulizia dei file temporanei e dei .bbl/.w18 alla fine di OGNI compilazione di successo
$cleanup_mode = 1;

# 2. Elenco dei file extra da rimuovere oltre a quelli standard (.aux, .log, .toc)
$clean_ext = 'bbl bcf run.xml w18 synctex.gz fdb_latexmk fls';