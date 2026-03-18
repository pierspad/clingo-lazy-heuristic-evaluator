




```python
python -m venv .venv

source .venv/bin/activate

pip install -r requirements.txt
```

clingo currently has a bug, to patch and build it from the `clingo-modified` directory, run the following commands from the root of the project:

```bash
sh ./patch_and_build_clingo/setup_clingo.sh
```
