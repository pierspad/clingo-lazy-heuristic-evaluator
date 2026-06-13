#include "clingo/heuristic_propagator.hh"
#include "tests.hh"
#include <catch2/catch_test_macros.hpp>

namespace Clingo {
namespace Test {



TEST_CASE("lazy-heuristic-propagator-decisions", "[clingo][heuristic]") {
    MessageVec messages;
    ModelVec models;
    Logger logger = [&messages](WarningCode code, char const *msg) {
        messages.emplace_back(code, msg);
    };







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
            heuristic("heuristic(a(X), 10, 0, true) :- item(X), alpha_not(c(X)).").
            heuristic("heuristic(z(1), 2, 0, true).").
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
            heuristic("heuristic(a(X), 10, 0, true) :- item(X), alpha_not(c(X)).").
            heuristic("heuristic(z(1), 2, 0, true).").
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
            heuristic("heuristic(a(X), 10, 0, true) :- item(X), clingo_not(c(X)).").
            heuristic("heuristic(z(1), 2, 0, true).").
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
            heuristic("heuristic(a(X), 10, 0, true) :- item(X), clingo_not(c(X)).").
            heuristic("heuristic(z(1), 2, 0, true).").
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
            heuristic("heuristic(a(X), W, 10, true) :- item(X), W = #count { Y : d(Y) }.").
            heuristic("heuristic(z(1), 1, 0, true).").
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
            heuristic("heuristic(b(X), W, 0, true) :- x(X), alpha_not(c(X)), S = #sum { Y : c(Y) }, W = ((n+1)*S)+X.").
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
            heuristic("heuristic(a(1), 10, 0, true).").
            heuristic("heuristic(a(1), 5, 100, false).").
            heuristic("heuristic(a(2), 6, 0, true).").
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
            heuristic("heuristic(a(1), 10, 0, true).").
            heuristic("heuristic(a(2), 5, 100, true).").
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
            heuristic("heuristic(unknown(1), 100, 0, true).").
            heuristic("heuristic(a(1), 1, 0, true).").
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


    SECTION("clingo-like malformed rule string is rejected") {
        Control ctl{{"0"}, logger, 20};
        HeuristicPropagator propagator;
        ctl.register_propagator(propagator, true);
        ctl.add("base", {}, R"(
            { a(1) }.
            heuristic("invalid(a(1), 1, 0, true).").
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_THROWS(test_solve(ctl.solve(), models));
    }






}

} // namespace Test
} // namespace Clingo
