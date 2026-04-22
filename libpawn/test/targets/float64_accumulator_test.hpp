#pragma once
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Float64Target qaClear and qaRead", "[accumulator][float64]") {
    p::Float64Target target;
    target.qaClear();
    p::Number result = target.qaRead();
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(0.0).margin(0.001));
}

TEST_CASE("Float64Target qaAdd", "[accumulator][float64]") {
    p::Float64Target target;
    p::Number a = target.toNumber(5.0);
    target.qaClear();
    target.qaAdd(a);
    p::Number result = target.qaRead();
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(5.0).margin(0.001));
}

TEST_CASE("Float64Target qaFma", "[accumulator][float64]") {
    p::Float64Target target;
    p::Number a = target.toNumber(2.0);
    p::Number b = target.toNumber(3.0);
    target.qaClear();
    target.qaFma(a, b);
    p::Number result = target.qaRead();
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(6.0).margin(0.01));
}

TEST_CASE("Float64Target qaFms", "[accumulator][float64]") {
    p::Float64Target target;
    p::Number a = target.toNumber(2.0);
    p::Number b = target.toNumber(3.0);
    target.qaClear();
    target.qaFms(a, b);
    p::Number result = target.qaRead();
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(-6.0).margin(0.01));
}

TEST_CASE("Float64Target qaNeg", "[accumulator][float64]") {
    p::Float64Target target;
    p::Number a = target.toNumber(5.0);
    target.qaClear();
    target.qaAdd(a);
    target.qaNeg();
    p::Number result = target.qaRead();
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(-5.0).margin(0.001));
}