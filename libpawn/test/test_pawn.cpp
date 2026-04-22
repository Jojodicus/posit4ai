#define CATCH_CONFIG_MAIN
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Float32Target creation", "[target]") {
    p::Float32Target target;
    REQUIRE(target.dataWidth == 32);
}

TEST_CASE("Number conversion float <-> Number", "[conversion]") {
    p::Float32Target target;
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.14f).margin(0.01f));
}