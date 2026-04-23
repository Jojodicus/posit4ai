#include "libpawn.hpp"
#include "takum.hpp"
#include <cstring>
#include <cmath>

namespace p
{
    static inline takum::takum12 roundTakum12(double d)
    {
        return takum::takum12(d);
    }
}

p::Takum12Target::Takum12Target() : FloatTarget(12)
{
    acc = new takum::takum12(0.0);
}

p::Number p::Takum12Target::toNumber(float f) { return toNumber(static_cast<double>(f)); }
p::Number p::Takum12Target::toNumber(double d)
{
    return p::Number{takum::takum12(d).bits()};
}
p::Number p::Takum12Target::toNumber(int32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum12Target::toNumber(uint32_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum12Target::toNumber(int64_t i) { return toNumber(static_cast<double>(i)); }
p::Number p::Takum12Target::toNumber(uint64_t i) { return toNumber(static_cast<double>(i)); }

double p::Takum12Target::toDouble(p::Number n) { return toFloat(n); }
float p::Takum12Target::toFloat(p::Number n)
{
    return static_cast<float>(takum::takum12::from_bits(n.bits).to_double());
}
int32_t p::Takum12Target::toInt32(p::Number n)
{
    return static_cast<int32_t>(takum::takum12::from_bits(n.bits).to_int64());
}
uint32_t p::Takum12Target::toUint32(p::Number n)
{
    return static_cast<uint32_t>(takum::takum12::from_bits(n.bits).to_int64());
}
int64_t p::Takum12Target::toInt64(p::Number n)
{
    return takum::takum12::from_bits(n.bits).to_int64();
}
uint64_t p::Takum12Target::toUint64(p::Number n)
{
    return static_cast<uint64_t>(takum::takum12::from_bits(n.bits).to_int64());
}
std::string p::Takum12Target::toString(p::Number n)
{
    return std::to_string(takum::takum12::from_bits(n.bits).to_double());
}

p::Number p::Takum12Target::add(p::Number a, p::Number b)
{
    auto result = takum::takum12::from_bits(a.bits) + takum::takum12::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum12Target::sub(p::Number a, p::Number b)
{
    auto result = takum::takum12::from_bits(a.bits) - takum::takum12::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum12Target::mul(p::Number a, p::Number b)
{
    auto result = takum::takum12::from_bits(a.bits) * takum::takum12::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum12Target::div(p::Number a, p::Number b)
{
    auto result = takum::takum12::from_bits(a.bits) / takum::takum12::from_bits(b.bits);
    return p::Number{result.bits()};
}
p::Number p::Takum12Target::neg(p::Number a)
{
    auto t = takum::takum12::from_bits(a.bits);
    return p::Number{(-t).bits()};
}
p::Number p::Takum12Target::abs(p::Number a)
{
    auto t = takum::takum12::from_bits(a.bits);
    if (t.is_zero() || t.is_nar()) return a;
    return p::Number{takum::takum12(t.to_double() < 0 ? -t.to_double() : t.to_double()).bits()};
}
p::Number p::Takum12Target::sqrt(p::Number a)
{
    auto t = takum::takum12::from_bits(a.bits);
    if (t.is_zero() || t.is_nar()) return a;
    return p::Number{takum::takum12(std::sqrt(t.to_double())).bits()};
}
p::Number p::Takum12Target::relu(p::Number a)
{
    auto t = takum::takum12::from_bits(a.bits);
    double v = t.to_double();
    return p::Number{(v < 0 ? takum::takum12(0.0) : t).bits()};
}

void p::Takum12Target::qaClear() { *reinterpret_cast<takum::takum12 *>(acc) = takum::takum12(0.0); }

void p::Takum12Target::qaAdd(p::Number a)
{
    *reinterpret_cast<takum::takum12 *>(acc) += takum::takum12::from_bits(a.bits);
}

void p::Takum12Target::qaFma(p::Number a, p::Number b)
{
    *reinterpret_cast<takum::takum12 *>(acc) += takum::takum12::from_bits(a.bits) * takum::takum12::from_bits(b.bits);
}

void p::Takum12Target::qaFms(p::Number a, p::Number b)
{
    *reinterpret_cast<takum::takum12 *>(acc) -= takum::takum12::from_bits(a.bits) * takum::takum12::from_bits(b.bits);
}

void p::Takum12Target::qaNeg() { *reinterpret_cast<takum::takum12 *>(acc) = -*reinterpret_cast<takum::takum12 *>(acc); }

p::Number p::Takum12Target::qaRead()
{
    return p::Number{reinterpret_cast<takum::takum12 *>(acc)->bits()};
}