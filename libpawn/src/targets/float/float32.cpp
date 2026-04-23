#include "libpawn.hpp"
#include <bit>
#include <cstring>
#include <cmath>

p::Float32Target::Float32Target() : FloatTarget(32)
{
    acc = new float(0.0f);
}

p::Number p::Float32Target::toNumber(float f)
{
    return p::Number{std::bit_cast<uint32_t>(f)}; // 0x0000XXXX
}
p::Number p::Float32Target::toNumber(double d) { return toNumber(static_cast<float>(d)); }
p::Number p::Float32Target::toNumber(int32_t i) { return toNumber(static_cast<float>(i)); }
p::Number p::Float32Target::toNumber(uint32_t i) { return toNumber(static_cast<float>(i)); }
p::Number p::Float32Target::toNumber(int64_t i) { return toNumber(static_cast<float>(i)); }
p::Number p::Float32Target::toNumber(uint64_t i) { return toNumber(static_cast<float>(i)); }
float p::Float32Target::toFloat(p::Number n)
{
    return std::bit_cast<float>(static_cast<uint32_t>(n.bits));
}
double p::Float32Target::toDouble(p::Number n) { return toFloat(n); }
int32_t p::Float32Target::toInt32(p::Number n) { return static_cast<int32_t>(toFloat(n)); }
uint32_t p::Float32Target::toUint32(p::Number n) { return static_cast<uint32_t>(toFloat(n)); }
int64_t p::Float32Target::toInt64(p::Number n) { return static_cast<int64_t>(toFloat(n)); }
uint64_t p::Float32Target::toUint64(p::Number n) { return static_cast<uint64_t>(toFloat(n)); }
std::string p::Float32Target::toString(p::Number n) { return std::to_string(toFloat(n)); }

p::Number p::Float32Target::add(p::Number a, p::Number b) { return toNumber(toFloat(a) + toFloat(b)); }
p::Number p::Float32Target::sub(p::Number a, p::Number b) { return toNumber(toFloat(a) - toFloat(b)); }
p::Number p::Float32Target::mul(p::Number a, p::Number b) { return toNumber(toFloat(a) * toFloat(b)); }
p::Number p::Float32Target::div(p::Number a, p::Number b) { return toNumber(toFloat(a) / toFloat(b)); }
p::Number p::Float32Target::neg(p::Number a) { return toNumber(-toFloat(a)); }
p::Number p::Float32Target::abs(p::Number a)
{
    double v = toFloat(a);
    return toNumber(v < 0 ? -v : v);
}
p::Number p::Float32Target::sqrt(p::Number a) { return toNumber(std::sqrt(toFloat(a))); }
p::Number p::Float32Target::relu(p::Number a)
{
    double v = toFloat(a);
    return toNumber(v < 0 ? 0 : v);
}

void p::Float32Target::qaClear() { *reinterpret_cast<float *>(acc) = 0; }
void p::Float32Target::qaAdd(p::Number a) { *reinterpret_cast<float *>(acc) += toFloat(a); }
void p::Float32Target::qaFma(p::Number a, p::Number b) { *reinterpret_cast<float *>(acc) += toFloat(a) * toFloat(b); }
void p::Float32Target::qaFms(p::Number a, p::Number b) { *reinterpret_cast<float *>(acc) -= toFloat(a) * toFloat(b); }
void p::Float32Target::qaNeg() { *reinterpret_cast<float *>(acc) = -*reinterpret_cast<float *>(acc); }
p::Number p::Float32Target::qaRead() { return toNumber(*reinterpret_cast<float *>(acc)); }