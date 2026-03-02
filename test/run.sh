
clingo ./encoding.lp ./instance.lp --stats --configuration=frumpy > info-run-cli.txt

python3 1-run_with_propagator.py > info-run-py.txt