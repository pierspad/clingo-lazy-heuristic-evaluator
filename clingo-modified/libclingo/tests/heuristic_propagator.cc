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
            __heuristic(__target(choose), dom, __weight(self), __priority(1), true).
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
            __heuristic(__target(choose), dom, __weight(self), __priority(1), true).
            #show choose/1.
        )");
        ctl.ground({{"base", {}}}, nullptr);
        REQUIRE_FALSE(test_solve(ctl.solve(), models).is_satisfiable());
        REQUIRE(models.empty());
    }
}

} // namespace Test
} // namespace Clingo
