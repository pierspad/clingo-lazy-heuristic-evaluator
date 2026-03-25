# crea un venv se non esiste chiamato .venv
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi

# attiva il venv
source .venv/bin/activate

