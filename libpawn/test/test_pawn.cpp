#define CATCH_CONFIG_MAIN
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("UniversalTarget creation", "[target]") {
    p::UniversalTarget target(32);
    REQUIRE(target.dataWidth == 32);
}

TEST_CASE("Number conversion float <-> Number", "[conversion]") {
    p::UniversalTarget target(32);
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.14f).margin(0.01f));
}