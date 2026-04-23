#include "libpawn.hpp"
#include <bit>
#include <cstring>
#include <cmath>

namespace p
{
    static inline float roundBfloat16(float f)
    {
        uint32_t bits = std::bit_cast<uint32_t>(f);
        bits &= 0xFFFF0000u;
        return std::bit_cast<float>(bits);
    }
}

p::Bfloat16Target::Bfloat16Target() : FloatTarget(16)
{
    acc = new float;
}

p::Number p::Bfloat16Target::toNumber(float f)
{
    return p::Number{std::bit_cast<uint32_t>(f)};
}
p::Number p::Bfloat16Target::toNumber(double d) { return toNumber(static_cast<float>(d)); }
p::Number p::Bfloat16Target::toNumber(int32_t i) { return toNumber(static_cast<float>(i)); }
p::Number p::Bfloat16Target::toNumber(uint32_t i) { return toNumber(static_cast<float>(i)); }
p::Number p::Bfloat16Target::toNumber(int64_t i) { return toNumber(static_cast<float>(i)); }
p::Number p::Bfloat16Target::toNumber(uint64_t i) { return toNumber(static_cast<float>(i)); }
float p::Bfloat16Target::toFloat(p::Number n)
{
    uint32_t bits = static_cast<uint32_t>(n.bits);
    bits &= 0xFFFF0000u;
    return std::bit_cast<float>(bits);
}
double p::Bfloat16Target::toDouble(p::Number n) { return toFloat(n); }
int32_t p::Bfloat16Target::toInt32(p::Number n) { return static_cast<int32_t>(toFloat(n)); }
uint32_t p::Bfloat16Target::toUint32(p::Number n) { return static_cast<uint32_t>(toFloat(n)); }
int64_t p::Bfloat16Target::toInt64(p::Number n) { return static_cast<int64_t>(toFloat(n)); }
uint64_t p::Bfloat16Target::toUint64(p::Number n) { return static_cast<uint64_t>(toFloat(n)); }
std::string p::Bfloat16Target::toString(p::Number n) { return std::to_string(toFloat(n)); }

p::Number p::Bfloat16Target::add(p::Number a, p::Number b)
{
    float result = toFloat(a) + toFloat(b);
    return p::Number{std::bit_cast<uint32_t>(result) & 0xFFFF0000u};
}
p::Number p::Bfloat16Target::sub(p::Number a, p::Number b)
{
    float result = toFloat(a) - toFloat(b);
    return p::Number{std::bit_cast<uint32_t>(result) & 0xFFFF0000u};
}
p::Number p::Bfloat16Target::mul(p::Number a, p::Number b)
{
    float result = toFloat(a) * toFloat(b);
    return p::Number{std::bit_cast<uint32_t>(result) & 0xFFFF0000u};
}
p::Number p::Bfloat16Target::div(p::Number a, p::Number b)
{
    float result = toFloat(a) / toFloat(b);
    return p::Number{std::bit_cast<uint32_t>(result) & 0xFFFF0000u};
}
p::Number p::Bfloat16Target::neg(p::Number a) { return toNumber(-toFloat(a)); }
p::Number p::Bfloat16Target::abs(p::Number a)
{
    double v = toFloat(a);
    return toNumber(v < 0 ? -v : v);
}
p::Number p::Bfloat16Target::sqrt(p::Number a) { return toNumber(std::sqrt(toFloat(a))); }
p::Number p::Bfloat16Target::relu(p::Number a)
{
    double v = toFloat(a);
    return toNumber(v < 0 ? 0 : v);
}

void p::Bfloat16Target::qaClear() { *reinterpret_cast<float *>(acc) = 0; }

void p::Bfloat16Target::qaAdd(p::Number a)
{
    *reinterpret_cast<float *>(acc) += toFloat(a);
    *reinterpret_cast<float *>(acc) = p::roundBfloat16(*reinterpret_cast<float *>(acc));
}

void p::Bfloat16Target::qaFma(p::Number a, p::Number b)
{
    *reinterpret_cast<float *>(acc) += toFloat(a) * toFloat(b);
    *reinterpret_cast<float *>(acc) = p::roundBfloat16(*reinterpret_cast<float *>(acc));
}

void p::Bfloat16Target::qaFms(p::Number a, p::Number b)
{
    *reinterpret_cast<float *>(acc) -= toFloat(a) * toFloat(b);
    *reinterpret_cast<float *>(acc) = p::roundBfloat16(*reinterpret_cast<float *>(acc));
}

void p::Bfloat16Target::qaNeg() { *reinterpret_cast<float *>(acc) = -*reinterpret_cast<float *>(acc); }

p::Number p::Bfloat16Target::qaRead()
{
    return toNumber(*reinterpret_cast<float *>(acc));
}