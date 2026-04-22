#pragma once
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Float32Target qaClear and qaRead", "[accumulator][float32]") {
    p::Float32Target target;
    target.qaClear();
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(0.0f).margin(0.001f));
}

TEST_CASE("Float32Target qaAdd", "[accumulator][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(5.0f);
    target.qaClear();
    target.qaAdd(a);
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(5.0f).margin(0.001f));
}

TEST_CASE("Float32Target qaFma", "[accumulator][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    target.qaClear();
    target.qaFma(a, b);
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(6.0f).margin(0.01f));
}

TEST_CASE("Float32Target qaFms", "[accumulator][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    target.qaClear();
    target.qaFms(a, b);
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-6.0f).margin(0.01f));
}

TEST_CASE("Float32Target qaNeg", "[accumulator][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(5.0f);
    target.qaClear();
    target.qaAdd(a);
    target.qaNeg();
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-5.0f).margin(0.001f));
}