
clingo ./encoding.lp ./instance.lp --stats --configuration=frumpy > run-cli.txt

python3 1-run_with_propagator.py > run-py.txt