# compare clingo 5.8.0 on classical BSP with
# clingo-modified with lazy heuristics on the same problem, but with a non-ground heuristic directive

echo "=========================================================="
echo "=== Esecuzione Clingo standard 5.8.0 su __BSP.lp ==="
time clingo __BSP.lp __.common_range.lp --stats=2 --heuristic=Domain -n 1

echo "=========================================================="
echo "=== Esecuzione Clingo modificato su _2_non_ground.lp ==="
time ~/Desktop/clingo-lazy-heuristics/clingo-modified/build/bin/clingo _2_non_ground.lp __.common_range.lp --stats=2 -n 1
