# compare clingo 5.8.0 on classical BSP with
# clingo-modified with lazy heuristics on the same problem, but with a non-ground heuristic directive


clingo 5.8.0 __BSP.lp __.common_range.lp 

~/Desktop/clingo-lazy-heuristics/clingo-modified/build/bin/clingo __BSP.lp __.common_range.lp _1_grounded.lp _2_non_ground.lp