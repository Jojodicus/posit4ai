#pragma once
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Takum32Target creation", "[target][takum32]") {
    p::Takum32Target target;
    REQUIRE(target.dataWidth == 32);
}

TEST_CASE("Takum32Target toNumber from float", "[conversion][takum32]") {
    p::Takum32Target target;
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.14f).margin(0.001f));
}

TEST_CASE("Takum32Target toNumber from double", "[conversion][takum32]") {
    p::Takum32Target target;
    p::Number n = target.toNumber(3.141592653589793);
    double d = target.toDouble(n);
    REQUIRE(d == Catch::Approx(3.14159).margin(0.0001));
}

TEST_CASE("Takum32Target toNumber from int32_t", "[conversion][takum32]") {
    p::Takum32Target target;
    p::Number n = target.toNumber(int32_t(42));
    int32_t i = target.toInt32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Takum32Target toNumber from uint32_t", "[conversion][takum32]") {
    p::Takum32Target target;
    p::Number n = target.toNumber(uint32_t(42));
    uint32_t i = target.toUint32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Takum32Target toNumber from int64_t", "[conversion][takum32]") {
    p::Takum32Target target;
    p::Number n = target.toNumber(int64_t(42));
    int64_t i = target.toInt64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Takum32Target toNumber from uint64_t", "[conversion][takum32]") {
    p::Takum32Target target;
    p::Number n = target.toNumber(uint64_t(42));
    uint64_t i = target.toUint64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Takum32Target add", "[arithmetic][takum32]") {
    p::Takum32Target target;
    p::Number a = target.toNumber(1.5f);
    p::Number b = target.toNumber(2.5f);
    p::Number result = target.add(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.001f));
}

TEST_CASE("Takum32Target sub", "[arithmetic][takum32]") {
    p::Takum32Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.sub(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(2.0f).margin(0.001f));
}

TEST_CASE("Takum32Target mul", "[arithmetic][takum32]") {
    p::Takum32Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.mul(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(6.0f).margin(0.001f));
}

TEST_CASE("Takum32Target div", "[arithmetic][takum32]") {
    p::Takum32Target target;
    p::Number a = target.toNumber(6.0f);
    p::Number b = target.toNumber(2.0f);
    p::Number result = target.div(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(3.0f).margin(0.001f));
}

TEST_CASE("Takum32Target neg", "[arithmetic][takum32]") {
    p::Takum32Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number result = target.neg(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-5.0f).margin(0.001f));
}

TEST_CASE("Takum32Target abs", "[arithmetic][takum32]") {
    p::Takum32Target target;
    p::Number a = target.toNumber(-5.0f);
    p::Number result = target.abs(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(5.0f).margin(0.001f));
}

TEST_CASE("Takum32Target sqrt", "[arithmetic][takum32]") {
    p::Takum32Target target;
    p::Number a = target.toNumber(16.0f);
    p::Number result = target.sqrt(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.01f));
}

TEST_CASE("Takum32Target relu", "[arithmetic][takum32]") {
    p::Takum32Target target;
    p::Number neg = target.toNumber(-5.0f);
    p::Number pos = target.toNumber(5.0f);
    p::Number resultNeg = target.relu(neg);
    p::Number resultPos = target.relu(pos);
    float negResult = target.toFloat(resultNeg);
    float posResult = target.toFloat(resultPos);
    REQUIRE(negResult == Catch::Approx(0.0f).margin(0.001f));
    REQUIRE(posResult == Catch::Approx(5.0f).margin(0.001f));
}

TEST_CASE("Takum32Target toString", "[conversion][takum32]") {
    p::Takum32Target target;
    p::Number n = target.toNumber(3.14f);
    std::string s = target.toString(n);
    REQUIRE(s.length() > 0);
}