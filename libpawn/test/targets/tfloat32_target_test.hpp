#pragma once
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Tfloat32Target creation", "[target][tfloat32]") {
    p::Tfloat32Target target;
    REQUIRE(target.dataWidth == 19);
}

TEST_CASE("Tfloat32Target toNumber from float", "[conversion][tfloat32]") {
    p::Tfloat32Target target;
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.14f).margin(0.001f));
}

TEST_CASE("Tfloat32Target toNumber from double", "[conversion][tfloat32]") {
    p::Tfloat32Target target;
    p::Number n = target.toNumber(3.141592653589793);
    double d = target.toDouble(n);
    REQUIRE(d == Catch::Approx(3.14111328125).margin(0.001));
}

TEST_CASE("Tfloat32Target toNumber from int32_t", "[conversion][tfloat32]") {
    p::Tfloat32Target target;
    p::Number n = target.toNumber(int32_t(42));
    int32_t i = target.toInt32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Tfloat32Target toNumber from uint32_t", "[conversion][tfloat32]") {
    p::Tfloat32Target target;
    p::Number n = target.toNumber(uint32_t(42));
    uint32_t i = target.toUint32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Tfloat32Target toNumber from int64_t", "[conversion][tfloat32]") {
    p::Tfloat32Target target;
    p::Number n = target.toNumber(int64_t(42));
    int64_t i = target.toInt64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Tfloat32Target toNumber from uint64_t", "[conversion][tfloat32]") {
    p::Tfloat32Target target;
    p::Number n = target.toNumber(uint64_t(42));
    uint64_t i = target.toUint64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Tfloat32Target add", "[arithmetic][tfloat32]") {
    p::Tfloat32Target target;
    p::Number a = target.toNumber(1.5f);
    p::Number b = target.toNumber(2.5f);
    p::Number result = target.add(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.001f));
}

TEST_CASE("Tfloat32Target sub", "[arithmetic][tfloat32]") {
    p::Tfloat32Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.sub(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(2.0f).margin(0.001f));
}

TEST_CASE("Tfloat32Target mul", "[arithmetic][tfloat32]") {
    p::Tfloat32Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.mul(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(6.0f).margin(0.001f));
}

TEST_CASE("Tfloat32Target div", "[arithmetic][tfloat32]") {
    p::Tfloat32Target target;
    p::Number a = target.toNumber(6.0f);
    p::Number b = target.toNumber(2.0f);
    p::Number result = target.div(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(3.0f).margin(0.001f));
}

TEST_CASE("Tfloat32Target neg", "[arithmetic][tfloat32]") {
    p::Tfloat32Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number result = target.neg(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-5.0f).margin(0.001f));
}

TEST_CASE("Tfloat32Target abs", "[arithmetic][tfloat32]") {
    p::Tfloat32Target target;
    p::Number a = target.toNumber(-5.0f);
    p::Number result = target.abs(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(5.0f).margin(0.001f));
}

TEST_CASE("Tfloat32Target sqrt", "[arithmetic][tfloat32]") {
    p::Tfloat32Target target;
    p::Number a = target.toNumber(16.0f);
    p::Number result = target.sqrt(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.01f));
}

TEST_CASE("Tfloat32Target relu", "[arithmetic][tfloat32]") {
    p::Tfloat32Target target;
    p::Number neg = target.toNumber(-5.0f);
    p::Number pos = target.toNumber(5.0f);
    p::Number resultNeg = target.relu(neg);
    p::Number resultPos = target.relu(pos);
    REQUIRE(target.toFloat(resultNeg) == Catch::Approx(0.0f).margin(0.001f));
    REQUIRE(target.toFloat(resultPos) == Catch::Approx(5.0f).margin(0.001f));
}

TEST_CASE("Tfloat32Target toString", "[conversion][tfloat32]") {
    p::Tfloat32Target target;
    p::Number n = target.toNumber(1.0f);
    std::string s = target.toString(n);
    REQUIRE(s.length() > 0);
}

TEST_CASE("Tfloat32Target special values", "[special][tfloat32]") {
    p::Tfloat32Target target;
    p::Number zero = target.toNumber(0.0f);
    p::Number inf = target.toNumber(std::numeric_limits<float>::infinity());
    p::Number ninf = target.toNumber(-std::numeric_limits<float>::infinity());
    p::Number nan = target.toNumber(std::numeric_limits<float>::quiet_NaN());

    REQUIRE(target.toFloat(zero) == Catch::Approx(0.0f).margin(0.001f));
    REQUIRE(std::isinf(target.toFloat(inf)));
    REQUIRE(std::isinf(target.toFloat(ninf)));
    REQUIRE(std::isnan(target.toFloat(nan)));
}