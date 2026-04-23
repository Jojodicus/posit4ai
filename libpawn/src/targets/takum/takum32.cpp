#include "libpawn.hpp"
#include "takum.hpp"
#include <cstring>
#include <cmath>

p::Takum32Target::Takum32Target() : FloatTarget(32)
{
    acc = new takum::takum32(0.0);
}

p::Number p::Takum32Target::toNumber(float f) { return toNumber(static_cast<double>(f)); }
p::Number p::Takum32Target::toNumber(double d)
{
    return p::Number{takum::takum32(d).bits()};
}
p::Number p::Takum32Target::toNumber(int32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum32Target::toNumber(uint32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum32Target::toNumber(int64_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum32Target::toNumber(uint64_t i) { return toNumber(static_cast<double>(i)); }

double p::Takum32Target::toDouble(p::Number n) { return toFloat(n); }
float p::Takum32Target::toFloat(p::Number n)
{
    return static_cast<float>(takum::takum32::from_bits(n.bits).to_double());
}
int32_t p::Takum32Target::toInt32(p::Number n)
{
    return static_cast<int32_t>(takum::takum32::from_bits(n.bits).to_int64());
}
uint32_t p::Takum32Target::toUint32(p::Number n)
{
    return static_cast<uint32_t>(takum::takum32::from_bits(n.bits).to_int64());
}
int64_t p::Takum32Target::toInt64(p::Number n)
{
    return takum::takum32::from_bits(n.bits).to_int64();
}
uint64_t p::Takum32Target::toUint64(p::Number n)
{
    return static_cast<uint64_t>(takum::takum32::from_bits(n.bits).to_int64());
}
std::string p::Takum32Target::toString(p::Number n)
{
    return std::to_string(takum::takum32::from_bits(n.bits).to_double());
}

p::Number p::Takum32Target::add(p::Number a, p::Number b)
{
    auto result = takum::takum32::from_bits(a.bits) + takum::takum32::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum32Target::sub(p::Number a, p::Number b)
{
    auto result = takum::takum32::from_bits(a.bits) - takum::takum32::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum32Target::mul(p::Number a, p::Number b)
{
    auto result = takum::takum32::from_bits(a.bits) * takum::takum32::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum32Target::div(p::Number a, p::Number b)
{
    auto result = takum::takum32::from_bits(a.bits) / takum::takum32::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum32Target::neg(p::Number a)
{
    auto t = takum::takum32::from_bits(a.bits);
    return p::Number{(-t).bits()};
}
p::Number p::Takum32Target::abs(p::Number a)
{
    auto t = takum::takum32::from_bits(a.bits);
    if (t.is_zero() || t.is_nar()) return a;
    return p::Number{takum::takum32(t.to_double() < 0 ? -t.to_double() : t.to_double()).bits()};
}
p::Number p::Takum32Target::sqrt(p::Number a)
{
    auto t = takum::takum32::from_bits(a.bits);
    if (t.is_zero() || t.is_nar()) return a;
    return p::Number{takum::takum32(std::sqrt(t.to_double())).bits()};
}
p::Number p::Takum32Target::relu(p::Number a)
{
    auto t = takum::takum32::from_bits(a.bits);
    double v = t.to_double();
    return p::Number{(v < 0 ? takum::takum32(0.0) : t).bits()};
}

void p::Takum32Target::qaClear() { *reinterpret_cast<takum::takum32 *>(acc) = takum::takum32(0.0); }

void p::Takum32Target::qaAdd(p::Number a)
{
    *reinterpret_cast<takum::takum32 *>(acc) += takum::takum32::from_bits(a.bits);
}

void p::Takum32Target::qaFma(p::Number a, p::Number b)
{
    *reinterpret_cast<takum::takum32 *>(acc) += takum::takum32::from_bits(a.bits) * takum::takum32::from_bits(b.bits);
}

void p::Takum32Target::qaFms(p::Number a, p::Number b)
{
    *reinterpret_cast<takum::takum32 *>(acc) -= takum::takum32::from_bits(a.bits) * takum::takum32::from_bits(b.bits);
}

void p::Takum32Target::qaNeg() { *reinterpret_cast<takum::takum32 *>(acc) = -*reinterpret_cast<takum::takum32 *>(acc); }

p::Number p::Takum32Target::qaRead()
{
    return p::Number{reinterpret_cast<takum::takum32 *>(acc)->bits()};
}