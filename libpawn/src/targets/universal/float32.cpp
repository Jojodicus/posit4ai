#include "libpawn.hpp"
#include <cstring>
#include <cmath>

p::Float32Target::Float32Target() : FloatTarget(32)
{
    acc = new float(0.0f);
}

p::Number p::Float32Target::toNumber(float f) { return toNumber(static_cast<double>(f)); }
p::Number p::Float32Target::toNumber(double d)
{
    uint64_t bits;
    std::memcpy(&bits, &d, sizeof(d));
    return p::Number{ bits };
}
p::Number p::Float32Target::toNumber(int32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Float32Target::toNumber(uint32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Float32Target::toNumber(int64_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Float32Target::toNumber(uint64_t i) { return toNumber(static_cast<double>(i)); }
float p::Float32Target::toFloat(p::Number n) { return static_cast<float>(toDouble(n)); }
double p::Float32Target::toDouble(p::Number n)
{
    double d;
    std::memcpy(&d, &n.bits, sizeof(d));
    return d;
}
int32_t p::Float32Target::toInt32(p::Number n) { return static_cast<int32_t>(toDouble(n)); }
uint32_t p::Float32Target::toUint32(p::Number n) { return static_cast<uint32_t>(toDouble(n)); }
int64_t p::Float32Target::toInt64(p::Number n) { return static_cast<int64_t>(toDouble(n)); }
uint64_t p::Float32Target::toUint64(p::Number n) { return static_cast<uint64_t>(toDouble(n)); }
std::string p::Float32Target::toString(p::Number n) { return std::to_string(toDouble(n)); }

p::Number p::Float32Target::add(p::Number a, p::Number b) { return toNumber(toDouble(a) + toDouble(b)); }
p::Number p::Float32Target::sub(p::Number a, p::Number b) { return toNumber(toDouble(a) - toDouble(b)); }
p::Number p::Float32Target::mul(p::Number a, p::Number b) { return toNumber(toDouble(a) * toDouble(b)); }
p::Number p::Float32Target::div(p::Number a, p::Number b) { return toNumber(toDouble(a) / toDouble(b)); }
p::Number p::Float32Target::neg(p::Number a) { return toNumber(-toDouble(a)); }
p::Number p::Float32Target::abs(p::Number a) { double v = toDouble(a); return toNumber(v < 0 ? -v : v); }
p::Number p::Float32Target::sqrt(p::Number a) { return toNumber(std::sqrt(toDouble(a))); }
p::Number p::Float32Target::relu(p::Number a) { double v = toDouble(a); return toNumber(v < 0 ? 0 : v); }

void p::Float32Target::qaClear() { *reinterpret_cast<float*>(acc) = 0; }
void p::Float32Target::qaAdd(p::Number a) { *reinterpret_cast<float*>(acc) += toFloat(a); }
void p::Float32Target::qaFma(p::Number a, p::Number b) { *reinterpret_cast<float*>(acc) += toFloat(a) * toFloat(b); }
void p::Float32Target::qaFms(p::Number a, p::Number b) { *reinterpret_cast<float*>(acc) -= toFloat(a) * toFloat(b); }
void p::Float32Target::qaNeg() { *reinterpret_cast<float*>(acc) = -*reinterpret_cast<float*>(acc); }
p::Number p::Float32Target::qaRead() { return toNumber(*reinterpret_cast<float*>(acc)); }