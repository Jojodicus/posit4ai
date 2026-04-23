#pragma once
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Bfloat16Target creation", "[target][bfloat16]") {
    p::Bfloat16Target target;
    REQUIRE(target.dataWidth == 16);
}

TEST_CASE("Bfloat16Target toNumber from float", "[conversion][bfloat16]") {
    p::Bfloat16Target target;
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.125f).margin(0.01f));
}

TEST_CASE("Bfloat16Target toNumber from double", "[conversion][bfloat16]") {
    p::Bfloat16Target target;
    p::Number n = target.toNumber(3.141592653589793);
    double d = target.toDouble(n);
    REQUIRE(d == Catch::Approx(3.14159).margin(0.01));
}

TEST_CASE("Bfloat16Target toNumber from int32_t", "[conversion][bfloat16]") {
    p::Bfloat16Target target;
    p::Number n = target.toNumber(int32_t(42));
    int32_t i = target.toInt32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Bfloat16Target toNumber from uint32_t", "[conversion][bfloat16]") {
    p::Bfloat16Target target;
    p::Number n = target.toNumber(uint32_t(42));
    uint32_t i = target.toUint32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Bfloat16Target toNumber from int64_t", "[conversion][bfloat16]") {
    p::Bfloat16Target target;
    p::Number n = target.toNumber(int64_t(42));
    int64_t i = target.toInt64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Bfloat16Target toNumber from uint64_t", "[conversion][bfloat16]") {
    p::Bfloat16Target target;
    p::Number n = target.toNumber(uint64_t(42));
    uint64_t i = target.toUint64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Bfloat16Target add", "[arithmetic][bfloat16]") {
    p::Bfloat16Target target;
    p::Number a = target.toNumber(1.5f);
    p::Number b = target.toNumber(2.5f);
    p::Number result = target.add(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.01f));
}

TEST_CASE("Bfloat16Target sub", "[arithmetic][bfloat16]") {
    p::Bfloat16Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.sub(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(2.0f).margin(0.01f));
}

TEST_CASE("Bfloat16Target mul", "[arithmetic][bfloat16]") {
    p::Bfloat16Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.mul(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(6.0f).margin(0.01f));
}

TEST_CASE("Bfloat16Target div", "[arithmetic][bfloat16]") {
    p::Bfloat16Target target;
    p::Number a = target.toNumber(6.0f);
    p::Number b = target.toNumber(2.0f);
    p::Number result = target.div(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(3.0f).margin(0.01f));
}

TEST_CASE("Bfloat16Target neg", "[arithmetic][bfloat16]") {
    p::Bfloat16Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number result = target.neg(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-5.0f).margin(0.01f));
}

TEST_CASE("Bfloat16Target abs", "[arithmetic][bfloat16]") {
    p::Bfloat16Target target;
    p::Number a = target.toNumber(-5.0f);
    p::Number result = target.abs(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(5.0f).margin(0.01f));
}

TEST_CASE("Bfloat16Target sqrt", "[arithmetic][bfloat16]") {
    p::Bfloat16Target target;
    p::Number a = target.toNumber(16.0f);
    p::Number result = target.sqrt(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.1f));
}

TEST_CASE("Bfloat16Target relu", "[arithmetic][bfloat16]") {
    p::Bfloat16Target target;
    p::Number neg = target.toNumber(-5.0f);
    p::Number pos = target.toNumber(5.0f);
    p::Number resultNeg = target.relu(neg);
    p::Number resultPos = target.relu(pos);
    REQUIRE(target.toFloat(resultNeg) == Catch::Approx(0.0f).margin(0.01f));
    REQUIRE(target.toFloat(resultPos) == Catch::Approx(5.0f).margin(0.01f));
}

TEST_CASE("Bfloat16Target toString", "[conversion][bfloat16]") {
    p::Bfloat16Target target;
    p::Number n = target.toNumber(3.125f);
    std::string s = target.toString(n);
    REQUIRE(s.find("3.125") != std::string::npos);
}

TEST_CASE("Bfloat16Target special values", "[special][bfloat16]") {
    p::Bfloat16Target target;
    p::Number zero = target.toNumber(0.0f);
    p::Number inf = target.toNumber(std::numeric_limits<float>::infinity());
    p::Number ninf = target.toNumber(-std::numeric_limits<float>::infinity());
    p::Number nan = target.toNumber(std::numeric_limits<float>::quiet_NaN());

    REQUIRE(target.toFloat(zero) == Catch::Approx(0.0f).margin(0.01f));
    REQUIRE(std::isinf(target.toFloat(inf)));
    REQUIRE(std::isinf(target.toFloat(ninf)));
    REQUIRE(std::isnan(target.toFloat(nan)));
}