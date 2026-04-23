#include "libpawn.hpp"
#include "takum.hpp"
#include <cstring>
#include <cmath>

p::Takum48Target::Takum48Target() : FloatTarget(48)
{
    acc = new takum::takum48(0.0);
}

p::Number p::Takum48Target::toNumber(float f) { return toNumber(static_cast<double>(f)); }
p::Number p::Takum48Target::toNumber(double d)
{
    return p::Number{takum::takum48(d).bits()};
}
p::Number p::Takum48Target::toNumber(int32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum48Target::toNumber(uint32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum48Target::toNumber(int64_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum48Target::toNumber(uint64_t i) { return toNumber(static_cast<double>(i)); }

double p::Takum48Target::toDouble(p::Number n) { return toFloat(n); }
float p::Takum48Target::toFloat(p::Number n)
{
    return static_cast<float>(takum::takum48::from_bits(n.bits).to_double());
}
int32_t p::Takum48Target::toInt32(p::Number n)
{
    return static_cast<int32_t>(takum::takum48::from_bits(n.bits).to_int64());
}
uint32_t p::Takum48Target::toUint32(p::Number n)
{
    return static_cast<uint32_t>(takum::takum48::from_bits(n.bits).to_int64());
}
int64_t p::Takum48Target::toInt64(p::Number n)
{
    return takum::takum48::from_bits(n.bits).to_int64();
}
uint64_t p::Takum48Target::toUint64(p::Number n)
{
    return static_cast<uint64_t>(takum::takum48::from_bits(n.bits).to_int64());
}
std::string p::Takum48Target::toString(p::Number n)
{
    return std::to_string(takum::takum48::from_bits(n.bits).to_double());
}

p::Number p::Takum48Target::add(p::Number a, p::Number b)
{
    auto result = takum::takum48::from_bits(a.bits) + takum::takum48::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum48Target::sub(p::Number a, p::Number b)
{
    auto result = takum::takum48::from_bits(a.bits) - takum::takum48::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum48Target::mul(p::Number a, p::Number b)
{
    auto result = takum::takum48::from_bits(a.bits) * takum::takum48::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum48Target::div(p::Number a, p::Number b)
{
    auto result = takum::takum48::from_bits(a.bits) / takum::takum48::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum48Target::neg(p::Number a)
{
    auto t = takum::takum48::from_bits(a.bits);
    return p::Number{(-t).bits()};
}
p::Number p::Takum48Target::abs(p::Number a)
{
    auto t = takum::takum48::from_bits(a.bits);
    if (t.is_zero() || t.is_nar()) return a;
    return p::Number{takum::takum48(t.to_double() < 0 ? -t.to_double() : t.to_double()).bits()};
}
p::Number p::Takum48Target::sqrt(p::Number a)
{
    auto t = takum::takum48::from_bits(a.bits);
    if (t.is_zero() || t.is_nar()) return a;
    return p::Number{takum::takum48(std::sqrt(t.to_double())).bits()};
}
p::Number p::Takum48Target::relu(p::Number a)
{
    auto t = takum::takum48::from_bits(a.bits);
    double v = t.to_double();
    return p::Number{(v < 0 ? takum::takum48(0.0) : t).bits()};
}

void p::Takum48Target::qaClear() { *reinterpret_cast<takum::takum48 *>(acc) = takum::takum48(0.0); }

void p::Takum48Target::qaAdd(p::Number a)
{
    *reinterpret_cast<takum::takum48 *>(acc) += takum::takum48::from_bits(a.bits);
}

void p::Takum48Target::qaFma(p::Number a, p::Number b)
{
    *reinterpret_cast<takum::takum48 *>(acc) += takum::takum48::from_bits(a.bits) * takum::takum48::from_bits(b.bits);
}

void p::Takum48Target::qaFms(p::Number a, p::Number b)
{
    *reinterpret_cast<takum::takum48 *>(acc) -= takum::takum48::from_bits(a.bits) * takum::takum48::from_bits(b.bits);
}

void p::Takum48Target::qaNeg() { *reinterpret_cast<takum::takum48 *>(acc) = -*reinterpret_cast<takum::takum48 *>(acc); }

p::Number p::Takum48Target::qaRead()
{
    return p::Number{reinterpret_cast<takum::takum48 *>(acc)->bits()};
}