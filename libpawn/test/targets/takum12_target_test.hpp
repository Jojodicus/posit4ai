#pragma once
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Takum12Target creation", "[target][takum12]") {
    p::Takum12Target target;
    REQUIRE(target.dataWidth == 12);
}

TEST_CASE("Takum12Target toNumber from float", "[conversion][takum12]") {
    p::Takum12Target target;
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.14f).margin(0.1f));
}

TEST_CASE("Takum12Target toNumber from double", "[conversion][takum12]") {
    p::Takum12Target target;
    p::Number n = target.toNumber(3.141592653589793);
    double d = target.toDouble(n);
    REQUIRE(d == Catch::Approx(3.125).margin(0.1));
}

TEST_CASE("Takum12Target toNumber from int32_t", "[conversion][takum12]") {
    p::Takum12Target target;
    p::Number n = target.toNumber(int32_t(42));
    int32_t i = target.toInt32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Takum12Target toNumber from uint32_t", "[conversion][takum12]") {
    p::Takum12Target target;
    p::Number n = target.toNumber(uint32_t(42));
    uint32_t i = target.toUint32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Takum12Target toNumber from int64_t", "[conversion][takum12]") {
    p::Takum12Target target;
    p::Number n = target.toNumber(int64_t(42));
    int64_t i = target.toInt64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Takum12Target toNumber from uint64_t", "[conversion][takum12]") {
    p::Takum12Target target;
    p::Number n = target.toNumber(uint64_t(42));
    uint64_t i = target.toUint64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Takum12Target add", "[arithmetic][takum12]") {
    p::Takum12Target target;
    p::Number a = target.toNumber(1.5f);
    p::Number b = target.toNumber(2.5f);
    p::Number result = target.add(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.1f));
}

TEST_CASE("Takum12Target sub", "[arithmetic][takum12]") {
    p::Takum12Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.sub(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(2.0f).margin(0.1f));
}

TEST_CASE("Takum12Target mul", "[arithmetic][takum12]") {
    p::Takum12Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.mul(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(6.0f).margin(0.1f));
}

TEST_CASE("Takum12Target div", "[arithmetic][takum12]") {
    p::Takum12Target target;
    p::Number a = target.toNumber(6.0f);
    p::Number b = target.toNumber(2.0f);
    p::Number result = target.div(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(3.0f).margin(0.1f));
}

TEST_CASE("Takum12Target neg", "[arithmetic][takum12]") {
    p::Takum12Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number result = target.neg(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-5.0f).margin(0.01f));
}

TEST_CASE("Takum12Target abs", "[arithmetic][takum12]") {
    p::Takum12Target target;
    p::Number a = target.toNumber(-5.0f);
    p::Number result = target.abs(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(5.0f).margin(0.01f));
}

TEST_CASE("Takum12Target sqrt", "[arithmetic][takum12]") {
    p::Takum12Target target;
    p::Number a = target.toNumber(16.0f);
    p::Number result = target.sqrt(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.1f));
}

TEST_CASE("Takum12Target relu", "[arithmetic][takum12]") {
    p::Takum12Target target;
    p::Number neg = target.toNumber(-5.0f);
    p::Number pos = target.toNumber(5.0f);
    p::Number resultNeg = target.relu(neg);
    p::Number resultPos = target.relu(pos);
    float negResult = target.toFloat(resultNeg);
    float posResult = target.toFloat(resultPos);
    REQUIRE(negResult == Catch::Approx(0.0f).margin(0.01f));
    REQUIRE(posResult == Catch::Approx(5.0f).margin(0.1f));
}

TEST_CASE("Takum12Target toString", "[conversion][takum12]") {
    p::Takum12Target target;
    p::Number n = target.toNumber(3.14f);
    std::string s = target.toString(n);
    REQUIRE(s.length() > 0);
}