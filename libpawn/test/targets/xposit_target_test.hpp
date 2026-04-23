#pragma once
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("XpositTarget creation", "[target][xposit]") {
    p::XpositTarget target;
    REQUIRE(target.dataWidth == 64);
}

TEST_CASE("XpositTarget toNumber from float", "[conversion][xposit]") {
    p::XpositTarget target;
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.14f).margin(0.1f));
}

TEST_CASE("XpositTarget toNumber from double", "[conversion][xposit]") {
    p::XpositTarget target;
    p::Number n = target.toNumber(3.141592653589793);
    double d = target.toDouble(n);
    REQUIRE(d == Catch::Approx(3.141592653589793).margin(0.01));
}

TEST_CASE("XpositTarget toNumber from int32_t", "[conversion][xposit]") {
    p::XpositTarget target;
    p::Number n = target.toNumber(int32_t(42));
    int32_t i = target.toInt32(n);
    REQUIRE(i == 42);
}

TEST_CASE("XpositTarget toNumber from uint32_t", "[conversion][xposit]") {
    p::XpositTarget target;
    p::Number n = target.toNumber(uint32_t(42));
    uint32_t i = target.toUint32(n);
    REQUIRE(i == 42);
}

TEST_CASE("XpositTarget toNumber from int64_t", "[conversion][xposit]") {
    p::XpositTarget target;
    p::Number n = target.toNumber(int64_t(42));
    int64_t i = target.toInt64(n);
    REQUIRE(i == 42);
}

TEST_CASE("XpositTarget toNumber from uint64_t", "[conversion][xposit]") {
    p::XpositTarget target;
    p::Number n = target.toNumber(uint64_t(42));
    uint64_t i = target.toUint64(n);
    REQUIRE(i == 42);
}

TEST_CASE("XpositTarget toString", "[conversion][xposit]") {
    p::XpositTarget target;
    p::Number n = target.toNumber(42);
    std::string s = target.toString(n);
    REQUIRE(!s.empty());
}