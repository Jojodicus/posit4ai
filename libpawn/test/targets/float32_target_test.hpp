#pragma once
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Float32Target creation", "[target][float32]") {
    p::Float32Target target;
    REQUIRE(target.dataWidth == 32);
}

TEST_CASE("Float32Target toNumber from float", "[conversion][float32]") {
    p::Float32Target target;
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.14f).margin(0.001f));
}

TEST_CASE("Float32Target toNumber from double", "[conversion][float32]") {
    p::Float32Target target;
    p::Number n = target.toNumber(3.141592653589793);
    double d = target.toDouble(n);
    REQUIRE(d == Catch::Approx(3.141592653589793).margin(0.0001));
}

TEST_CASE("Float32Target toNumber from int32_t", "[conversion][float32]") {
    p::Float32Target target;
    p::Number n = target.toNumber(int32_t(42));
    int32_t i = target.toInt32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float32Target toNumber from uint32_t", "[conversion][float32]") {
    p::Float32Target target;
    p::Number n = target.toNumber(uint32_t(42));
    uint32_t i = target.toUint32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float32Target toNumber from int64_t", "[conversion][float32]") {
    p::Float32Target target;
    p::Number n = target.toNumber(int64_t(42));
    int64_t i = target.toInt64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float32Target toNumber from uint64_t", "[conversion][float32]") {
    p::Float32Target target;
    p::Number n = target.toNumber(uint64_t(42));
    uint64_t i = target.toUint64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float32Target add", "[arithmetic][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(1.5f);
    p::Number b = target.toNumber(2.5f);
    p::Number result = target.add(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.001f));
}

TEST_CASE("Float32Target sub", "[arithmetic][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.sub(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(2.0f).margin(0.001f));
}

TEST_CASE("Float32Target mul", "[arithmetic][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.mul(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(6.0f).margin(0.001f));
}

TEST_CASE("Float32Target div", "[arithmetic][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(6.0f);
    p::Number b = target.toNumber(2.0f);
    p::Number result = target.div(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(3.0f).margin(0.001f));
}

TEST_CASE("Float32Target neg", "[arithmetic][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number result = target.neg(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-5.0f).margin(0.001f));
}

TEST_CASE("Float32Target abs", "[arithmetic][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(-5.0f);
    p::Number result = target.abs(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(5.0f).margin(0.001f));
}

TEST_CASE("Float32Target sqrt", "[arithmetic][float32]") {
    p::Float32Target target;
    p::Number a = target.toNumber(16.0f);
    p::Number result = target.sqrt(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.01f));
}

TEST_CASE("Float32Target relu", "[arithmetic][float32]") {
    p::Float32Target target;
    p::Number neg = target.toNumber(-5.0f);
    p::Number pos = target.toNumber(5.0f);
    p::Number resultNeg = target.relu(neg);
    p::Number resultPos = target.relu(pos);
    REQUIRE(target.toFloat(resultNeg) == Catch::Approx(0.0f).margin(0.001f));
    REQUIRE(target.toFloat(resultPos) == Catch::Approx(5.0f).margin(0.001f));
}

TEST_CASE("Float32Target toString", "[conversion][float32]") {
    p::Float32Target target;
    p::Number n = target.toNumber(3.14f);
    std::string s = target.toString(n);
    REQUIRE(s.find("3.14") != std::string::npos);
}

TEST_CASE("Float32Target special values", "[special][float32]") {
    p::Float32Target target;
    p::Number zero = target.toNumber(0.0f);
    p::Number inf = target.toNumber(std::numeric_limits<float>::infinity());
    p::Number ninf = target.toNumber(-std::numeric_limits<float>::infinity());
    p::Number nan = target.toNumber(std::numeric_limits<float>::quiet_NaN());

    REQUIRE(target.toFloat(zero) == Catch::Approx(0.0f).margin(0.001f));
    REQUIRE(std::isinf(target.toFloat(inf)));
    REQUIRE(std::isinf(target.toFloat(ninf)));
    REQUIRE(std::isnan(target.toFloat(nan)));
}