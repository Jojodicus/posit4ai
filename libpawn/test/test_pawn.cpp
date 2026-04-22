#define CATCH_CONFIG_MAIN
#include <catch_amalgamated.hpp>
#include "libpawn.hpp"

TEST_CASE("Float32Target creation", "[target]") {
    p::Float32Target target;
    REQUIRE(target.dataWidth == 32);
}

TEST_CASE("Float64Target creation", "[target]") {
    p::Float64Target target;
    REQUIRE(target.dataWidth == 64);
}

TEST_CASE("Float32Target toNumber from float", "[conversion]") {
    p::Float32Target target;
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.14f).margin(0.001f));
}

TEST_CASE("Float32Target toNumber from double", "[conversion]") {
    p::Float32Target target;
    p::Number n = target.toNumber(3.141592653589793);
    double d = target.toDouble(n);
    REQUIRE(d == Catch::Approx(3.141592653589793).margin(0.0001));
}

TEST_CASE("Float64Target toNumber from float", "[conversion]") {
    p::Float64Target target;
    p::Number n = target.toNumber(3.14f);
    float f = target.toFloat(n);
    REQUIRE(f == Catch::Approx(3.14f).margin(0.001f));
}

TEST_CASE("Float64Target toNumber from double", "[conversion]") {
    p::Float64Target target;
    p::Number n = target.toNumber(3.14159265358979323846);
    double d = target.toDouble(n);
    REQUIRE(d == Catch::Approx(3.14159265358979323846).margin(0.0001));
}

TEST_CASE("Float32Target toNumber from int32_t", "[conversion]") {
    p::Float32Target target;
    p::Number n = target.toNumber(int32_t(42));
    int32_t i = target.toInt32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float32Target toNumber from uint32_t", "[conversion]") {
    p::Float32Target target;
    p::Number n = target.toNumber(uint32_t(42));
    uint32_t i = target.toUint32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float32Target toNumber from int64_t", "[conversion]") {
    p::Float32Target target;
    p::Number n = target.toNumber(int64_t(42));
    int64_t i = target.toInt64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float32Target toNumber from uint64_t", "[conversion]") {
    p::Float32Target target;
    p::Number n = target.toNumber(uint64_t(42));
    uint64_t i = target.toUint64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float64Target toNumber from int32_t", "[conversion]") {
    p::Float64Target target;
    p::Number n = target.toNumber(int32_t(42));
    int32_t i = target.toInt32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float64Target toNumber from uint32_t", "[conversion]") {
    p::Float64Target target;
    p::Number n = target.toNumber(uint32_t(42));
    uint32_t i = target.toUint32(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float64Target toNumber from int64_t", "[conversion]") {
    p::Float64Target target;
    p::Number n = target.toNumber(int64_t(42));
    int64_t i = target.toInt64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float64Target toNumber from uint64_t", "[conversion]") {
    p::Float64Target target;
    p::Number n = target.toNumber(uint64_t(42));
    uint64_t i = target.toUint64(n);
    REQUIRE(i == 42);
}

TEST_CASE("Float32Target add", "[arithmetic]") {
    p::Float32Target target;
    p::Number a = target.toNumber(1.5f);
    p::Number b = target.toNumber(2.5f);
    p::Number result = target.add(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.001f));
}

TEST_CASE("Float32Target sub", "[arithmetic]") {
    p::Float32Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.sub(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(2.0f).margin(0.001f));
}

TEST_CASE("Float32Target mul", "[arithmetic]") {
    p::Float32Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    p::Number result = target.mul(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(6.0f).margin(0.001f));
}

TEST_CASE("Float32Target div", "[arithmetic]") {
    p::Float32Target target;
    p::Number a = target.toNumber(6.0f);
    p::Number b = target.toNumber(2.0f);
    p::Number result = target.div(a, b);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(3.0f).margin(0.001f));
}

TEST_CASE("Float32Target neg", "[arithmetic]") {
    p::Float32Target target;
    p::Number a = target.toNumber(5.0f);
    p::Number result = target.neg(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-5.0f).margin(0.001f));
}

TEST_CASE("Float32Target abs", "[arithmetic]") {
    p::Float32Target target;
    p::Number a = target.toNumber(-5.0f);
    p::Number result = target.abs(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(5.0f).margin(0.001f));
}

TEST_CASE("Float32Target sqrt", "[arithmetic]") {
    p::Float32Target target;
    p::Number a = target.toNumber(16.0f);
    p::Number result = target.sqrt(a);
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(4.0f).margin(0.01f));
}

TEST_CASE("Float32Target relu", "[arithmetic]") {
    p::Float32Target target;
    p::Number neg = target.toNumber(-5.0f);
    p::Number pos = target.toNumber(5.0f);
    p::Number resultNeg = target.relu(neg);
    p::Number resultPos = target.relu(pos);
    REQUIRE(target.toFloat(resultNeg) == Catch::Approx(0.0f).margin(0.001f));
    REQUIRE(target.toFloat(resultPos) == Catch::Approx(5.0f).margin(0.001f));
}

TEST_CASE("Float64Target add", "[arithmetic]") {
    p::Float64Target target;
    p::Number a = target.toNumber(1.5);
    p::Number b = target.toNumber(2.5);
    p::Number result = target.add(a, b);
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(4.0).margin(0.001));
}

TEST_CASE("Float64Target sub", "[arithmetic]") {
    p::Float64Target target;
    p::Number a = target.toNumber(5.0);
    p::Number b = target.toNumber(3.0);
    p::Number result = target.sub(a, b);
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(2.0).margin(0.001));
}

TEST_CASE("Float64Target mul", "[arithmetic]") {
    p::Float64Target target;
    p::Number a = target.toNumber(2.0);
    p::Number b = target.toNumber(3.0);
    p::Number result = target.mul(a, b);
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(6.0).margin(0.001));
}

TEST_CASE("Float64Target div", "[arithmetic]") {
    p::Float64Target target;
    p::Number a = target.toNumber(6.0);
    p::Number b = target.toNumber(2.0);
    p::Number result = target.div(a, b);
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(3.0).margin(0.001));
}

TEST_CASE("Float64Target neg", "[arithmetic]") {
    p::Float64Target target;
    p::Number a = target.toNumber(5.0);
    p::Number result = target.neg(a);
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(-5.0).margin(0.001));
}

TEST_CASE("Float64Target abs", "[arithmetic]") {
    p::Float64Target target;
    p::Number a = target.toNumber(-5.0);
    p::Number result = target.abs(a);
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(5.0).margin(0.001));
}

TEST_CASE("Float64Target sqrt", "[arithmetic]") {
    p::Float64Target target;
    p::Number a = target.toNumber(16.0);
    p::Number result = target.sqrt(a);
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(4.0).margin(0.01));
}

TEST_CASE("Float64Target relu", "[arithmetic]") {
    p::Float64Target target;
    p::Number neg = target.toNumber(-5.0);
    p::Number pos = target.toNumber(5.0);
    p::Number resultNeg = target.relu(neg);
    p::Number resultPos = target.relu(pos);
    REQUIRE(target.toDouble(resultNeg) == Catch::Approx(0.0).margin(0.001));
    REQUIRE(target.toDouble(resultPos) == Catch::Approx(5.0).margin(0.001));
}

TEST_CASE("Float32Target qaClear and qaRead", "[accumulator]") {
    p::Float32Target target;
    target.qaClear();
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(0.0f).margin(0.001f));
}

TEST_CASE("Float32Target qaAdd", "[accumulator]") {
    p::Float32Target target;
    p::Number a = target.toNumber(5.0f);
    target.qaClear();
    target.qaAdd(a);
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(5.0f).margin(0.001f));
}

TEST_CASE("Float32Target qaFma", "[accumulator]") {
    p::Float32Target target;
    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);
    target.qaClear();
    target.qaFma(a, b);
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(6.0f).margin(0.01f));
}

TEST_CASE("Float32Target qaNeg", "[accumulator]") {
    p::Float32Target target;
    p::Number a = target.toNumber(5.0f);
    target.qaClear();
    target.qaAdd(a);
    target.qaNeg();
    p::Number result = target.qaRead();
    float r = target.toFloat(result);
    REQUIRE(r == Catch::Approx(-5.0f).margin(0.001f));
}

TEST_CASE("Float64Target qaClear and qaRead", "[accumulator]") {
    p::Float64Target target;
    target.qaClear();
    p::Number result = target.qaRead();
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(0.0).margin(0.001));
}

TEST_CASE("Float64Target qaAdd", "[accumulator]") {
    p::Float64Target target;
    p::Number a = target.toNumber(5.0);
    target.qaClear();
    target.qaAdd(a);
    p::Number result = target.qaRead();
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(5.0).margin(0.001));
}

TEST_CASE("Float64Target qaFma", "[accumulator]") {
    p::Float64Target target;
    p::Number a = target.toNumber(2.0);
    p::Number b = target.toNumber(3.0);
    target.qaClear();
    target.qaFma(a, b);
    p::Number result = target.qaRead();
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(6.0).margin(0.01));
}

TEST_CASE("Float64Target qaNeg", "[accumulator]") {
    p::Float64Target target;
    p::Number a = target.toNumber(5.0);
    target.qaClear();
    target.qaAdd(a);
    target.qaNeg();
    p::Number result = target.qaRead();
    double r = target.toDouble(result);
    REQUIRE(r == Catch::Approx(-5.0).margin(0.001));
}

TEST_CASE("Float32Target toString", "[conversion]") {
    p::Float32Target target;
    p::Number n = target.toNumber(3.14f);
    std::string s = target.toString(n);
    REQUIRE(s.find("3.14") != std::string::npos);
}

TEST_CASE("Float64Target toString", "[conversion]") {
    p::Float64Target target;
    p::Number n = target.toNumber(3.14159265358979);
    std::string s = target.toString(n);
    REQUIRE(s.find("3.14") != std::string::npos);
}

TEST_CASE("Float32Target special values", "[special]") {
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

TEST_CASE("Float64Target special values", "[special]") {
    p::Float64Target target;
    p::Number zero = target.toNumber(0.0);
    p::Number inf = target.toNumber(std::numeric_limits<double>::infinity());
    p::Number ninf = target.toNumber(-std::numeric_limits<double>::infinity());
    p::Number nan = target.toNumber(std::numeric_limits<double>::quiet_NaN());

    REQUIRE(target.toDouble(zero) == Catch::Approx(0.0).margin(0.001));
    REQUIRE(std::isinf(target.toDouble(inf)));
    REQUIRE(std::isinf(target.toDouble(ninf)));
    REQUIRE(std::isnan(target.toDouble(nan)));
}