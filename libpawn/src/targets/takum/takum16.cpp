#include "libpawn.hpp"
#include "takum.hpp"
#include <cstring>
#include <cmath>

p::Takum16Target::Takum16Target() : FloatTarget(16)
{
    acc = new takum::takum16(0.0);
}

p::Number p::Takum16Target::toNumber(float f) { return toNumber(static_cast<double>(f)); }
p::Number p::Takum16Target::toNumber(double d)
{
    return p::Number{takum::takum16(d).bits()};
}
p::Number p::Takum16Target::toNumber(int32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum16Target::toNumber(uint32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum16Target::toNumber(int64_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum16Target::toNumber(uint64_t i) { return toNumber(static_cast<double>(i)); }

double p::Takum16Target::toDouble(p::Number n) { return toFloat(n); }
float p::Takum16Target::toFloat(p::Number n)
{
    return static_cast<float>(takum::takum16::from_bits(n.bits).to_double());
}
int32_t p::Takum16Target::toInt32(p::Number n)
{
    return static_cast<int32_t>(takum::takum16::from_bits(n.bits).to_int64());
}
uint32_t p::Takum16Target::toUint32(p::Number n)
{
    return static_cast<uint32_t>(takum::takum16::from_bits(n.bits).to_int64());
}
int64_t p::Takum16Target::toInt64(p::Number n)
{
    return takum::takum16::from_bits(n.bits).to_int64();
}
uint64_t p::Takum16Target::toUint64(p::Number n)
{
    return static_cast<uint64_t>(takum::takum16::from_bits(n.bits).to_int64());
}
std::string p::Takum16Target::toString(p::Number n)
{
    return std::to_string(takum::takum16::from_bits(n.bits).to_double());
}

p::Number p::Takum16Target::add(p::Number a, p::Number b)
{
    auto result = takum::takum16::from_bits(a.bits) + takum::takum16::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum16Target::sub(p::Number a, p::Number b)
{
    auto result = takum::takum16::from_bits(a.bits) - takum::takum16::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum16Target::mul(p::Number a, p::Number b)
{
    auto result = takum::takum16::from_bits(a.bits) * takum::takum16::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum16Target::div(p::Number a, p::Number b)
{
    auto result = takum::takum16::from_bits(a.bits) / takum::takum16::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum16Target::neg(p::Number a)
{
    auto t = takum::takum16::from_bits(a.bits);
    return p::Number{(-t).bits()};
}
p::Number p::Takum16Target::abs(p::Number a)
{
    auto t = takum::takum16::from_bits(a.bits);
    if (t.is_zero() || t.is_nar()) return a;
    return p::Number{takum::takum16(t.to_double() < 0 ? -t.to_double() : t.to_double()).bits()};
}
p::Number p::Takum16Target::sqrt(p::Number a)
{
    auto t = takum::takum16::from_bits(a.bits);
    if (t.is_zero() || t.is_nar()) return a;
    return p::Number{takum::takum16(std::sqrt(t.to_double())).bits()};
}
p::Number p::Takum16Target::relu(p::Number a)
{
    auto t = takum::takum16::from_bits(a.bits);
    double v = t.to_double();
    return p::Number{(v < 0 ? takum::takum16(0.0) : t).bits()};
}

void p::Takum16Target::qaClear() { *reinterpret_cast<takum::takum16 *>(acc) = takum::takum16(0.0); }

void p::Takum16Target::qaAdd(p::Number a)
{
    *reinterpret_cast<takum::takum16 *>(acc) += takum::takum16::from_bits(a.bits);
}

void p::Takum16Target::qaFma(p::Number a, p::Number b)
{
    *reinterpret_cast<takum::takum16 *>(acc) += takum::takum16::from_bits(a.bits) * takum::takum16::from_bits(b.bits);
}

void p::Takum16Target::qaFms(p::Number a, p::Number b)
{
    *reinterpret_cast<takum::takum16 *>(acc) -= takum::takum16::from_bits(a.bits) * takum::takum16::from_bits(b.bits);
}

void p::Takum16Target::qaNeg() { *reinterpret_cast<takum::takum16 *>(acc) = -*reinterpret_cast<takum::takum16 *>(acc); }

p::Number p::Takum16Target::qaRead()
{
    return p::Number{reinterpret_cast<takum::takum16 *>(acc)->bits()};
}