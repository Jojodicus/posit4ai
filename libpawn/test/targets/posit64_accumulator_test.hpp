#pragma once
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Posit64Target qaClear and qaRead", "[accumulator][posit64]") {
    p::Posit64Target target;
    target.qaClear();
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(0.0f).margin(0.001f));
}

TEST_CASE("Posit64Target qaAdd", "[accumulator][posit64]") {
    p::Posit64Target target;
    p::Number a = target.toNumber(5.0f);
    target.qaClear();
    target.qaAdd(a);
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(5.0f).margin(0.01f));
}

TEST_CASE("Posit64Target qaFma", "[accumulator][posit64]") {
    p::Posit64Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    target.qaClear();
    target.qaFma(a, b);
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(6.0f).margin(0.01f));
}

TEST_CASE("Posit64Target qaFms", "[accumulator][posit64]") {
    p::Posit64Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    target.qaClear();
    target.qaFms(a, b);
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-6.0f).margin(0.01f));
}

TEST_CASE("Posit64Target qaNeg", "[accumulator][posit64]") {
    p::Posit64Target target;
    p::Number a = target.toNumber(5.0f);
    target.qaClear();
    target.qaAdd(a);
    target.qaNeg();
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-5.0f).margin(0.01f));
}