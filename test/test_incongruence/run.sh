
clingo ../encoding.lp ../instance.lp --stats --configuration=frumpy > run-cli.txt

python3 python_clingo.py > run-py.txt