#include "clingo/heuristic_propagator.hh"
#include "tests.hh"
#include <catch2/catch_test_macros.hpp>

namespace Clingo {
namespace Test {

TEST_CASE("lazy-heuristic-aggregate-states", "[clingo][heuristic]") {
    SECTION("sum") {
        SumState state;
        state.add(4);
        state.add(-2);
        REQUIRE(state.result() == 2);
        state.remove(4);
        REQUIRE(state.result() == -2);
        state.reset();
        REQUIRE(state.result() == 0);
    }

    SECTION("count") {
        CountState state;
        state.add(10);
        state.add(20);
        REQUIRE(state.result() == 2);
        state.remove(10);
        REQUIRE(state.result() == 1);
        state.reset();
        REQUIRE(state.result() == 0);
    }

    SECTION("min with duplicates and empty state") {
        MinState state;
        state.add(7);
        state.add(3);
        state.add(3);
        REQUIRE(state.result() == 3);
        state.remove(3);
        REQUIRE(state.result() == 3);
        state.remove(3);
        REQUIRE(state.result() == 7);
        state.remove(7);
        REQUIRE(state.result() == 0);
    }

    SECTION("max with duplicates and empty state") {
        MaxState state;
        state.add(1);
        state.add(9);
        state.add(9);
        REQUIRE(state.result() == 9);
        state.remove(9);
        REQUIRE(state.result() == 9);
        state.remove(9);
        REQUIRE(state.result() == 1);
        state.remove(1);
        REQUIRE(state.result() == 0);
    }
}

TEST_CASE("lazy-heuristic-propagator-corner-cases", "[clingo][heuristic]") {
    MessageVec messages;
    ModelVec models;
    Logger logger = [&messages](WarningCode code, char const *msg) {
        messages.emplace_back(code, msg);
    };

    SECTION("empty domain has no trigger") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            #const n=0.
            dom(1..n).
            { choose(X) } :- dom(X).
            __heuristic(__target(choose), dom, __weight(self), __priority(1), __modifier(true)).
            #show choose/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{}}));
    }

    SECTION("unsat remains unsat") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1).
            { choose(X) } :- dom(X).
            :- not choose(1).
            :- choose(1).
            __heuristic(__target(choose), dom, __weight(self), __priority(1), __modifier(true)).
            #show choose/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_FALSE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models.empty());
    }
}

TEST_CASE("lazy-heuristic-propagator-decisions", "[clingo][heuristic]") {
    MessageVec messages;
    ModelVec models;
    Logger logger = [&messages](WarningCode code, char const *msg) {
        messages.emplace_back(code, msg);
    };

    SECTION("simple body uses self as weight") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1..3).
            1 { choose(X) : dom(X) } 1.
            __heuristic(__target(choose), dom, __weight(self), __priority(1), __modifier(true)).
            #show choose/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("choose", {Number(3)})}}));
    }

    SECTION("self uses the first target argument for multi-argument targets") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1,100). dom(3,1).
            1 { choose(X,Y) : dom(X,Y) } 1.
            __heuristic(__target(choose), dom,
                        __weight(self), __priority(1), __modifier(true)).
            #show choose/2.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("choose", {Number(3), Number(1)})}}));
    }

    SECTION("target argument binding feeds arithmetic expressions") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1,100). dom(3,1).
            1 { choose(X,Y) : dom(X,Y) } 1.
            __heuristic(__target(choose), dom, __bind_target_arg(y, 1),
                        __weight(y), __priority(1), __modifier(true)).
            #show choose/2.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("choose", {Number(1), Number(100)})}}));
    }

    SECTION("explicit body binding feeds arithmetic expressions") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1..3).
            score(1,10). score(2,5). score(3,7).
            body(X,W) :- dom(X), score(X,W).
            1 { choose(X) : dom(X) } 1.
            __heuristic(__target(choose), __body(body, __match(0, 0), __bind_arg(w, 1)),
                        __weight(w), __priority(1), __modifier(true)).
            #show choose/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("choose", {Number(1)})}}));
    }

    SECTION("filtered aggregate weights are target-specific") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1..2).
            source(1,5). source(2,9).
            1 { choose(X) : dom(X) } 1.
            __heuristic(__target(choose), dom,
                        __bind(s, __sum(source, 1, __filter(0, 0))),
                        __weight(s), __priority(1), __modifier(true)).
            #show choose/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("choose", {Number(2)})}}));
    }

    SECTION("local priority resolves only modifications of the same target") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1..2).
            mark(1).
            1 { choose(X) : dom(X) } 1.
            __heuristic(__target(choose), __body(mark, __match(0, 0)),
                        __weight(1), __priority(100), __modifier(true)).
            __heuristic(__target(choose), dom,
                        __weight(self), __priority(0), __modifier(true)).
            #show choose/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("choose", {Number(2)})}}));
    }

    SECTION("clingo-like string heuristic uses trail truth and false predicates") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            item(1..2).
            { a(X) } :- item(X).
            { b(X) } :- item(X).
            { c(X) } :- item(X).
            b(1).
            :- c(1).
            heuristic("heuristic(a(X), 1, 10, true) :- item(X), b(X), not_c(X).").
            #show a/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("a", {Number(1)})}}));
    }

    SECTION("clingo-like string heuristic delegates aggregates to auxiliary clingo") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            item(1..2).
            val(10;20;30).
            { a(X) } :- item(X).
            { b(X) } :- item(X).
            { c(X) } :- item(X).
            { d(Y) } :- val(Y).
            b(1).
            d(10).
            d(20).
            :- c(1).
            heuristic("heuristic(a(X), W, 10, true) :- item(X), b(X), not_c(X), W = #count { Y : d(Y) }.").
            #show a/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("a", {Number(1)})}}));
    }

    SECTION("clingo-like default syntax is alpha and sees free atoms as not_p") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            item(1).
            1 { a(1); z(1) } 1.
            { c(1) }.
            heuristic("heuristic(a(X), 10, 0, true) :- item(X), not_c(X).").
            heuristic(alpha, "heuristic(z(1), 2, 0, true).").
            #show a/1.
            #show z/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("a", {Number(1)})}}));
    }

    SECTION("clingo-like explicit alpha sees free atoms as not_p") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            item(1).
            1 { a(1); z(1) } 1.
            { c(1) }.
            heuristic(alpha, "heuristic(a(X), 10, 0, true) :- item(X), not_c(X).").
            heuristic(alpha, "heuristic(z(1), 2, 0, true).").
            #show a/1.
            #show z/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("a", {Number(1)})}}));
    }

    SECTION("clingo-like explicit clingo only sees false atoms as not_p") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            item(1).
            1 { a(1); z(1) } 1.
            { c(1) }.
            heuristic(clingo, "heuristic(a(X), 10, 0, true) :- item(X), not_c(X).").
            heuristic(alpha, "heuristic(z(1), 2, 0, true).").
            #show a/1.
            #show z/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("z", {Number(1)})}}));
    }

    SECTION("clingo-like explicit clingo sees false atoms as not_p") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            item(1).
            1 { a(1); z(1) } 1.
            { c(1) }.
            :- c(1).
            heuristic(clingo, "heuristic(a(X), 10, 0, true) :- item(X), not_c(X).").
            heuristic(alpha, "heuristic(z(1), 2, 0, true).").
            #show a/1.
            #show z/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("a", {Number(1)})}}));
    }

    SECTION("clingo-like aggregate count determines global weight") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            item(1).
            val(10;20;30).
            d(10;20).
            { d(30) }.
            :- d(30).
            1 { a(1); z(1) } 1.
            heuristic(alpha, "heuristic(a(X), W, 10, true) :- item(X), W = #count { Y : d(Y) }.").
            heuristic(alpha, "heuristic(z(1), 1, 0, true).").
            #show a/1.
            #show z/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("a", {Number(1)})}}));
    }

    SECTION("clingo-like auxiliary program receives n inferred from x domain") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            x(1..3).
            c(1).
            { c(X) } :- x(X), X > 1.
            1 { b(X) : x(X) } 1.
            heuristic(alpha, "heuristic(b(X), W, 0, true) :- x(X), not_c(X), S = #sum { Y : c(Y) }, W = ((n+1)*S)+X.").
            #show b/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("b", {Number(3)})}}));
    }

    SECTION("clingo-like local priority resolves candidates for the same target before global weight") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            1 { a(1); a(2) } 1.
            heuristic(alpha, "heuristic(a(1), 10, 0, true).").
            heuristic(alpha, "heuristic(a(1), 5, 100, false).").
            heuristic(alpha, "heuristic(a(2), 6, 0, true).").
            #show a/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("a", {Number(2)})}}));
    }

    SECTION("alpha string heuristic priority is a global rank") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            1 { a(1); a(2) } 1.
            heuristic(alpha, "heuristic(a(1), 10, 0, true).").
            heuristic(alpha, "heuristic(a(2), 5, 100, true).").
            #show a/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("a", {Number(2)})}}));
    }

    SECTION("__heuristic alpha priority is a global rank before weight") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1..2).
            hi(2).
            1 { a(X) : dom(X) } 1.
            __heuristic(__target(a), __body(dom, __match(0, 0)),
                        __weight(self), __priority(0), __modifier(true), __semantics(alpha)).
            __heuristic(__target(a), __body(hi, __match(0, 0)),
                        __weight(1), __priority(100), __modifier(true), __semantics(alpha)).
            #show a/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("a", {Number(2)})}}));
    }

    SECTION("clingo-like unmapped targets are ignored") {
        Control ctl{{"1", "--heuristic=Domain"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            1 { a(1); z(1) } 1.
            heuristic(alpha, "heuristic(unknown(1), 100, 0, true).").
            heuristic(alpha, "heuristic(a(1), 1, 0, true).").
            #show a/1.
            #show z/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models == ModelVec({{Function("a", {Number(1)})}}));
    }
}

TEST_CASE("lazy-heuristic-syntax-validation", "[clingo][heuristic]") {
    MessageVec messages;
    ModelVec models;
    Logger logger = [&messages](WarningCode code, char const *msg) {
        messages.emplace_back(code, msg);
    };

    SECTION("duplicate aggregate variable is rejected") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1).
            { choose(X) } :- dom(X).
            __heuristic(__target(choose), dom,
                        __bind(s, __sum(dom, 0)),
                        __bind(s, __count(dom, 0)),
                        __weight(s), __modifier(true)).
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_THROWS(test_solve(ctl.solve(), models));
    }

    SECTION("clingo-like malformed semantics is rejected") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            { a(1) }.
            heuristic(beta, "heuristic(a(1), 1, 0, true).").
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_THROWS(test_solve(ctl.solve(), models));
    }

    SECTION("negative aggregate index is rejected") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1).
            { choose(X) } :- dom(X).
            __heuristic(__target(choose), dom,
                        __bind(s, __sum(dom, -1)),
                        __weight(s), __modifier(true)).
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_THROWS(test_solve(ctl.solve(), models));
    }

    SECTION("explicit body without match is rejected") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1).
            body(1,10).
            { choose(X) } :- dom(X).
            __heuristic(__target(choose), __body(body, __bind_arg(w, 1)),
                        __weight(w), __modifier(true)).
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_THROWS(test_solve(ctl.solve(), models));
    }

    SECTION("duplicate body variable is rejected") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1).
            body(1,10,20).
            { choose(X) } :- dom(X).
            __heuristic(__target(choose),
                        __body(body, __match(0, 0), __bind_arg(w, 1), __bind_arg(w, 2)),
                        __weight(w), __modifier(true)).
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_THROWS(test_solve(ctl.solve(), models));
    }

    SECTION("duplicate target argument variable is rejected") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1).
            { choose(X) } :- dom(X).
            __heuristic(__target(choose), dom,
                        __bind_target_arg(w, 0),
                        __bind(w, __sum(dom, 0)),
                        __weight(w), __modifier(true)).
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_THROWS(test_solve(ctl.solve(), models));
    }

    SECTION("negative target argument index is rejected") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1).
            { choose(X) } :- dom(X).
            __heuristic(__target(choose), dom,
                        __bind_target_arg(w, -1),
                        __weight(w), __modifier(true)).
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_THROWS(test_solve(ctl.solve(), models));
    }

    SECTION("out-of-range target argument binding is rejected") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            dom(1).
            { choose(X) } :- dom(X).
            __heuristic(__target(choose), dom,
                        __bind_target_arg(w, 1),
                        __weight(w), __modifier(true)).
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_THROWS(test_solve(ctl.solve(), models));
    }
}

} // namespace Test
} // namespace Clingo
