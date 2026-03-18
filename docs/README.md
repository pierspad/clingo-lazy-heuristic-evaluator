




```python
python -m venv .venv

source .venv/bin/activate

pip install -r requirements.txt
```

clingo currently has a bug with re2c and needs to be patched

```bash
sh ./patch_and_build_clingo/setup_clingo.sh
```
