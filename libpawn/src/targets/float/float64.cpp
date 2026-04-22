#include "libpawn.hpp"
#include <bit>
#include <cstring>
#include <cmath>

p::Float64Target::Float64Target() : FloatTarget(64)
{
    acc = new double;
}

p::Number p::Float64Target::toNumber(float f) { return toNumber(static_cast<double>(f)); }
p::Number p::Float64Target::toNumber(double d)
{
    return p::Number{std::bit_cast<uint64_t>(d)};
}
p::Number p::Float64Target::toNumber(int32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Float64Target::toNumber(uint32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Float64Target::toNumber(int64_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Float64Target::toNumber(uint64_t i) { return toNumber(static_cast<double>(i)); }
float p::Float64Target::toFloat(p::Number n) { return static_cast<float>(toDouble(n)); }
double p::Float64Target::toDouble(p::Number n)
{
    return std::bit_cast<double>(n.bits);
}
int32_t p::Float64Target::toInt32(p::Number n) { return static_cast<int32_t>(toDouble(n)); }
uint32_t p::Float64Target::toUint32(p::Number n) { return static_cast<uint32_t>(toDouble(n)); }
int64_t p::Float64Target::toInt64(p::Number n) { return static_cast<int64_t>(toDouble(n)); }
uint64_t p::Float64Target::toUint64(p::Number n) { return static_cast<uint64_t>(toDouble(n)); }
std::string p::Float64Target::toString(p::Number n) { return std::to_string(toDouble(n)); }

p::Number p::Float64Target::add(p::Number a, p::Number b) { return toNumber(toDouble(a) + toDouble(b)); }
p::Number p::Float64Target::sub(p::Number a, p::Number b) { return toNumber(toDouble(a) - toDouble(b)); }
p::Number p::Float64Target::mul(p::Number a, p::Number b) { return toNumber(toDouble(a) * toDouble(b)); }
p::Number p::Float64Target::div(p::Number a, p::Number b) { return toNumber(toDouble(a) / toDouble(b)); }
p::Number p::Float64Target::neg(p::Number a) { return toNumber(-toDouble(a)); }
p::Number p::Float64Target::abs(p::Number a)
{
    double v = toDouble(a);
    return toNumber(v < 0 ? -v : v);
}
p::Number p::Float64Target::sqrt(p::Number a) { return toNumber(std::sqrt(toDouble(a))); }
p::Number p::Float64Target::relu(p::Number a)
{
    double v = toDouble(a);
    return toNumber(v < 0 ? 0 : v);
}

void p::Float64Target::qaClear() { *reinterpret_cast<double *>(acc) = 0; }
void p::Float64Target::qaAdd(p::Number a) { *reinterpret_cast<double *>(acc) += toDouble(a); }
void p::Float64Target::qaFma(p::Number a, p::Number b) { *reinterpret_cast<double *>(acc) += toDouble(a) * toDouble(b); }
void p::Float64Target::qaFms(p::Number a, p::Number b) { *reinterpret_cast<double *>(acc) -= toDouble(a) * toDouble(b); }
void p::Float64Target::qaNeg() { *reinterpret_cast<double *>(acc) = -*reinterpret_cast<double *>(acc); }
p::Number p::Float64Target::qaRead() { return toNumber(*reinterpret_cast<double *>(acc)); }