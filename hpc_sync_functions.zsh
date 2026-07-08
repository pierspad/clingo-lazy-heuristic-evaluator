# ============================================================
# Funzioni zsh per sync locale <-> HPC.
#
# Questo file vive DENTRO clingo-lazy-heuristics/ ed è tracciato da git:
# modificalo qui direttamente (non serve più tenerne una copia fuori).
# In ~/.zshrc basta una riga:
#
#   source ~/Desktop/Thesis/clingo-lazy-heuristics/hpc_sync_functions.zsh
#
# NON viene mai sincronizzato verso l'HPC: pushhpccode esclude se stesso
# esplicitamente (non avrebbe senso lì, e sourcearlo per errore da un altro
# checkout puntando altrove sarebbe un pasticcio).
#
# pushhpccode sincronizza anche swipl-moderno/ (sibling di
# clingo-lazy-heuristics, sia in locale che su HPC), esclusa la sua build/.
#
# Esclusioni locale-only (mai verso HPC), tutte PRIMA di --include='/*.sh'
# perché in rsync la prima regola che matcha vince:
#   - hpc_sync_functions.zsh (questo file)
#   - compile_all_local.sh (solo per compilare in locale)
#   - bench-runs-local/ (script adattati per girare solo in locale)
#   - test_folder/benchmark_folder_clingo/programs/runlim (binario compilato,
#     ABI/glibc specifica della macchina — e' in .gitignore ma rsync non lo
#     rispetta; senza questo exclude un push da locale sovrascrive in
#     silenzio il runlim ricompilato correttamente sul compute node remoto)
# ============================================================

function copyhpcgraphs() {
  local remote_host="spadafora@hpc"
  local base_remote_dir="~/clingo-lazy-heuristics/test_folder"
  local local_target="./clingo_hpc_graphs/"

  # Assicura che la directory di destinazione esista localmente
  mkdir -p "$local_target"

  # Elementi da sincronizzare, formato "sorgente_remota|nome_locale".
  # I due results.xlsx remoti (full run e smoke test) hanno lo stesso
  # basename: senza destinazione esplicita l'ultimo scaricato SOVRASCRIVEVA
  # l'altro in clingo_hpc_graphs/results.xlsx (successo il 2026-07-07:
  # l'xlsx della full run clobberato da quello dello smoke test). Con il
  # nome locale esplicito non c'è più ambiguità su quale campagna si guarda.
  local targets=(
    "graphs-native|"
    "graphs-prolog|"
    "graphs-comparison-native-prolog|"
    "benchmark_folder_clingo/output/results.xlsx|results-full.xlsx"
    "benchmark_folder_clingo/output-short-hpc/results.xlsx|results-short-hpc.xlsx"
    "benchmark_folder_clingo/eval.log|eval.log"
    "benchmark_folder_clingo/results.xml|results.xml"
    "benchmark_folder_clingo/results-short.xml|results-short.xml"
  )

  echo "🔄 Avvio sincronizzazione grafici e log analitici da HPC..."

  # Ciclo esplicito: file singoli con nome locale esplicito, cartelle (dst
  # vuota) dentro local_target mantenendo la struttura.
  local item src dst
  for item in $targets; do
    src="${item%%|*}"
    dst="${item##*|}"
    rsync -avz --progress \
      --include='*/' \
      "${remote_host}:${base_remote_dir}/${src}" \
      "${local_target}${dst}" 2>/dev/null || echo "⚠️  Nota: ${src} non ancora presente sull'HPC (normale se il benchmark non è finito)."
  done

  echo "✅ Sincronizzazione completata. Controlla la cartella: $local_target"
}

function pushhpccode() {
  # Risolve la root del repo dalla posizione di QUESTO file (zsh: %N = path
  # dello script sourcato), non da un path hardcoded — così funziona anche
  # se sposti il checkout altrove.
  local repo_root="${${(%):-%N}:A:h}"
  cd "$repo_root"
  local remote_target="hpc:~/clingo-lazy-heuristics/"
  local local_source="./"

  if [[ ! -d "clingo-native" && ! -d "clingo-prolog" ]]; then
    echo "❌ Errore: $repo_root non sembra la root di clingo-lazy-heuristics!"
    return 1
  fi

  echo "📤 Sincronizzazione mirata del codice verso HPC (escludendo grafici, cache e venv)..."

  # Nota: Le esclusioni specifiche di pattern annidati (.venv, build, ecc.) devono stare
  # PRIMA delle inclusioni globali come /test_folder/***, altrimenti rsync le include comunque.
  rsync -avz --progress \
    --exclude='.git/' \
    --exclude='.vscode/' \
    --exclude='**/.venv/' \
    --exclude='**/build/' \
    --exclude='**/CMakeFiles/' \
    --exclude='**/__pycache__/' \
    --exclude='*.pyc' \
    --exclude='**/graphs-native/' \
    --exclude='**/graphs-prolog/' \
    --exclude='**/graphs-comparison-native-prolog/' \
    --exclude='**/clingo_hpc_graphs/' \
    --exclude='/hpc_sync_functions.zsh' \
    --exclude='/compile_all_local.sh' \
    --exclude='/bench-runs-local/' \
    --exclude='**/programs/runlim' \
    --include='/*.sh' \
    --include='/clingo-native/***' \
    --include='/clingo-prolog/***' \
    --include='/test_folder/***' \
    --exclude='/*' \
    "$local_source" "$remote_target"

  # --- swipl-moderno: vive FUORI da clingo-lazy-heuristics, come sibling,
  # sia in locale (../swipl-moderno) sia su HPC (~/swipl-moderno). Va
  # sincronizzato a parte per lo stesso motivo per cui compile_all.sh lo
  # tratta come progetto separato. Portiamo download.sh + i sorgenti,
  # MAI build/ (grossa, e legata a un gcc/glibc specifico del nodo).
  local swipl_local="../swipl-moderno/"
  local swipl_remote="hpc:~/swipl-moderno/"
  if [[ -d "../swipl-moderno" ]]; then
    echo "📤 Sincronizzazione swipl-moderno verso HPC (esclusa build/)..."
    rsync -avz --progress \
      --exclude='**/build/' \
      --exclude='**/CMakeFiles/' \
      "$swipl_local" "$swipl_remote" \
      || echo "⚠️  Sync di swipl-moderno fallita (controlla il path ../swipl-moderno)."
  else
    echo "⚠️  Nota: ../swipl-moderno non trovato in locale (atteso come sibling di clingo-lazy-heuristics), salto."
  fi
}
