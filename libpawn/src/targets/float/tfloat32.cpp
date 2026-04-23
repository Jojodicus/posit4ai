#include "libpawn.hpp"
#include <bit>
#include <cstring>
#include <cmath>

namespace p
{
    static inline float roundTfloat32(float f)
    {
        uint32_t bits = std::bit_cast<uint32_t>(f);
        bits &= 0xFFFFF800u;
        return std::bit_cast<float>(bits);
    }
}

p::Tfloat32Target::Tfloat32Target() : FloatTarget(19)
{
    acc = new float;
}

p::Number p::Tfloat32Target::toNumber(float f)
{
    return p::Number{std::bit_cast<uint32_t>(f)};
}
p::Number p::Tfloat32Target::toNumber(double d) { return toNumber(static_cast<float>(d)); }
p::Number p::Tfloat32Target::toNumber(int32_t i) { return toNumber(static_cast<float>(i)); }
p::Number p::Tfloat32Target::toNumber(uint32_t i) { return toNumber(static_cast<float>(i)); }
p::Number p::Tfloat32Target::toNumber(int64_t i) { return toNumber(static_cast<float>(i)); }
p::Number p::Tfloat32Target::toNumber(uint64_t i) { return toNumber(static_cast<float>(i)); }
float p::Tfloat32Target::toFloat(p::Number n)
{
    uint32_t bits = static_cast<uint32_t>(n.bits);
    bits &= 0xFFFFF800u;
    return std::bit_cast<float>(bits);
}
double p::Tfloat32Target::toDouble(p::Number n) { return toFloat(n); }
int32_t p::Tfloat32Target::toInt32(p::Number n) { return static_cast<int32_t>(toFloat(n)); }
uint32_t p::Tfloat32Target::toUint32(p::Number n) { return static_cast<uint32_t>(toFloat(n)); }
int64_t p::Tfloat32Target::toInt64(p::Number n) { return static_cast<int64_t>(toFloat(n)); }
uint64_t p::Tfloat32Target::toUint64(p::Number n) { return static_cast<uint64_t>(toFloat(n)); }
std::string p::Tfloat32Target::toString(p::Number n) { return std::to_string(toFloat(n)); }

p::Number p::Tfloat32Target::add(p::Number a, p::Number b)
{
    float result = toFloat(a) + toFloat(b);
    return p::Number{std::bit_cast<uint32_t>(result) & 0xFFFFF800u};
}
p::Number p::Tfloat32Target::sub(p::Number a, p::Number b)
{
    float result = toFloat(a) - toFloat(b);
    return p::Number{std::bit_cast<uint32_t>(result) & 0xFFFFF800u};
}
p::Number p::Tfloat32Target::mul(p::Number a, p::Number b)
{
    float result = toFloat(a) * toFloat(b);
    return p::Number{std::bit_cast<uint32_t>(result) & 0xFFFFF800u};
}
p::Number p::Tfloat32Target::div(p::Number a, p::Number b)
{
    float result = toFloat(a) / toFloat(b);
    return p::Number{std::bit_cast<uint32_t>(result) & 0xFFFFF800u};
}
p::Number p::Tfloat32Target::neg(p::Number a) { return toNumber(-toFloat(a)); }
p::Number p::Tfloat32Target::abs(p::Number a)
{
    double v = toFloat(a);
    return toNumber(v < 0 ? -v : v);
}
p::Number p::Tfloat32Target::sqrt(p::Number a) { return toNumber(std::sqrt(toFloat(a))); }
p::Number p::Tfloat32Target::relu(p::Number a)
{
    double v = toFloat(a);
    return toNumber(v < 0 ? 0 : v);
}

void p::Tfloat32Target::qaClear() { *reinterpret_cast<float *>(acc) = 0; }

void p::Tfloat32Target::qaAdd(p::Number a)
{
    *reinterpret_cast<float *>(acc) += toFloat(a);
    *reinterpret_cast<float *>(acc) = p::roundTfloat32(*reinterpret_cast<float *>(acc));
}

void p::Tfloat32Target::qaFma(p::Number a, p::Number b)
{
    *reinterpret_cast<float *>(acc) += toFloat(a) * toFloat(b);
    *reinterpret_cast<float *>(acc) = p::roundTfloat32(*reinterpret_cast<float *>(acc));
}

void p::Tfloat32Target::qaFms(p::Number a, p::Number b)
{
    *reinterpret_cast<float *>(acc) -= toFloat(a) * toFloat(b);
    *reinterpret_cast<float *>(acc) = p::roundTfloat32(*reinterpret_cast<float *>(acc));
}

void p::Tfloat32Target::qaNeg() { *reinterpret_cast<float *>(acc) = -*reinterpret_cast<float *>(acc); }

p::Number p::Tfloat32Target::qaRead()
{
    return toNumber(*reinterpret_cast<float *>(acc));
}