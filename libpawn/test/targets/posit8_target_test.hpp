#pragma once
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Posit8Target creation", "[target][posit8]") {
    p::Posit8Target target;
    REQUIRE(target.dataWidth == 8);
}

TEST_CASE("Posit8Target toNumber from float", "[conversion][posit8]") {
    p::Posit8Target target;
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.14f).margin(0.5f));
}

TEST_CASE("Posit8Target toNumber from double", "[conversion][posit8]") {
    p::Posit8Target target;
    p::Number n = target.toNumber(3.141592653589793);
    double d = target.toDouble(n);
    REQUIRE(d == Catch::Approx(3.0).margin(0.5));
}

TEST_CASE("Posit8Target toNumber from int32_t", "[conversion][posit8]") {
    p::Posit8Target target;
    p::Number n = target.toNumber(int32_t(42));
    int32_t i = target.toInt32(n);
    REQUIRE(i == 40);  // Posit8 saturates small values
}

TEST_CASE("Posit8Target toNumber from uint32_t", "[conversion][posit8]") {
    p::Posit8Target target;
    p::Number n = target.toNumber(uint32_t(42));
    uint32_t i = target.toUint32(n);
    REQUIRE(i == 40);
}

TEST_CASE("Posit8Target toNumber from int64_t", "[conversion][posit8]") {
    p::Posit8Target target;
    p::Number n = target.toNumber(int64_t(42));
    int64_t i = target.toInt64(n);
    REQUIRE(i == 40);
}

TEST_CASE("Posit8Target toNumber from uint64_t", "[conversion][posit8]") {
    p::Posit8Target target;
    p::Number n = target.toNumber(uint64_t(42));
    uint64_t i = target.toUint64(n);
    REQUIRE(i == 40);
}

TEST_CASE("Posit8Target add", "[arithmetic][posit8]") {
    p::Posit8Target target;
    p::Number a = target.toNumber(1.5f);
    p::Number b = target.toNumber(2.5f);
    p::Number result = target.add(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.5f));
}

TEST_CASE("Posit8Target sub", "[arithmetic][posit8]") {
    p::Posit8Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.sub(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(2.0f).margin(0.5f));
}

TEST_CASE("Posit8Target mul", "[arithmetic][posit8]") {
    p::Posit8Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.mul(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(6.0f).margin(0.5f));
}

TEST_CASE("Posit8Target div", "[arithmetic][posit8]") {
    p::Posit8Target target;
    p::Number a = target.toNumber(6.0f);
    p::Number b = target.toNumber(2.0f);
    p::Number result = target.div(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(3.0f).margin(0.5f));
}

TEST_CASE("Posit8Target neg", "[arithmetic][posit8]") {
    p::Posit8Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number result = target.neg(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-5.0f).margin(0.5f));
}

TEST_CASE("Posit8Target abs", "[arithmetic][posit8]") {
    p::Posit8Target target;
    p::Number a = target.toNumber(-5.0f);
    p::Number result = target.abs(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(5.0f).margin(0.5f));
}

TEST_CASE("Posit8Target sqrt", "[arithmetic][posit8]") {
    p::Posit8Target target;
    p::Number a = target.toNumber(16.0f);
    p::Number result = target.sqrt(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.5f));
}

TEST_CASE("Posit8Target relu", "[arithmetic][posit8]") {
    p::Posit8Target target;
    p::Number neg = target.toNumber(-5.0f);
    p::Number pos = target.toNumber(5.0f);
    p::Number resultNeg = target.relu(neg);
    p::Number resultPos = target.relu(pos);
    float negResult = target.toFloat(resultNeg);
    float posResult = target.toFloat(resultPos);
    REQUIRE(negResult == Catch::Approx(0.0f).margin(0.1f));
    REQUIRE(posResult == Catch::Approx(5.0f).margin(0.5f));
}

TEST_CASE("Posit8Target toString", "[conversion][posit8]") {
    p::Posit8Target target;
    p::Number n = target.toNumber(3.14f);
    std::string s = target.toString(n);
    REQUIRE(s.length() > 0);
}