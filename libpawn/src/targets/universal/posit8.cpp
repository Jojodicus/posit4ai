#include "libpawn.hpp"
#include "universal.hpp"
#include <cmath>

namespace p
{
    Posit8Target::Posit8Target() : UniversalTarget(8) {
        quire = new Quire8();
    }

    Number Posit8Target::toNumber(float f) {
        return toNumber(static_cast<double>(f));
    }

    Number Posit8Target::toNumber(double d) {
        Posit8 p(d);
        return Number{posit_to_bits(p)};
    }

    Number Posit8Target::toNumber(int32_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit8Target::toNumber(uint32_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit8Target::toNumber(int64_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit8Target::toNumber(uint64_t i) {
        return toNumber(static_cast<double>(i));
    }

    float Posit8Target::toFloat(Number n) {
        return static_cast<float>(bits_to_posit<Posit8>(n.bits).operator double());
    }

    double Posit8Target::toDouble(Number n) {
        return bits_to_posit<Posit8>(n.bits).operator double();
    }

    int32_t Posit8Target::toInt32(Number n) {
        return static_cast<int32_t>(bits_to_posit<Posit8>(n.bits).operator int64_t());
    }

    uint32_t Posit8Target::toUint32(Number n) {
        double d = bits_to_posit<Posit8>(n.bits).operator double();
        if (d < 0) return 0;
        if (d > UINT32_MAX) return UINT32_MAX;
        return static_cast<uint32_t>(d);
    }

    int64_t Posit8Target::toInt64(Number n) {
        return bits_to_posit<Posit8>(n.bits).operator int64_t();
    }

    uint64_t Posit8Target::toUint64(Number n) {
        double d = bits_to_posit<Posit8>(n.bits).operator double();
        if (d < 0) return 0;
        if (d > UINT64_MAX) return UINT64_MAX;
        return static_cast<uint64_t>(d);
    }

    std::string Posit8Target::toString(Number n) {
        return std::to_string(bits_to_posit<Posit8>(n.bits).operator double());
    }

    Number Posit8Target::add(Number a, Number b) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        Posit8 pb = bits_to_posit<Posit8>(b.bits);
        return Number{posit_to_bits(pa + pb)};
    }

    Number Posit8Target::sub(Number a, Number b) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        Posit8 pb = bits_to_posit<Posit8>(b.bits);
        return Number{posit_to_bits(pa - pb)};
    }

    Number Posit8Target::mul(Number a, Number b) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        Posit8 pb = bits_to_posit<Posit8>(b.bits);
        return Number{posit_to_bits(pa * pb)};
    }

    Number Posit8Target::div(Number a, Number b) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        Posit8 pb = bits_to_posit<Posit8>(b.bits);
        return Number{posit_to_bits(pa / pb)};
    }

    Number Posit8Target::neg(Number a) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        return Number{posit_to_bits(-pa)};
    }

    Number Posit8Target::abs(Number a) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        double d = pa.operator double();
        if (d < 0) d = -d;
        return Number{posit_to_bits(Posit8(d))};
    }

    Number Posit8Target::sqrt(Number a) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        return Number{posit_to_bits(sw::universal::sqrt(pa))};
    }

    Number Posit8Target::relu(Number a) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        double d = pa.operator double();
        return Number{(d < 0 ? Posit8(0.0) : pa).bits().to_ull()};
    }

    void Posit8Target::qaClear() {
        reinterpret_cast<Quire8*>(quire)->clear();
    }

    void Posit8Target::qaAdd(Number a) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        *reinterpret_cast<Quire8*>(quire) += sw::universal::quire_mul(pa, Posit8(1.0));
    }

    void Posit8Target::qaFma(Number a, Number b) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        Posit8 pb = bits_to_posit<Posit8>(b.bits);
        *reinterpret_cast<Quire8*>(quire) += sw::universal::quire_mul(pa, pb);
    }

    void Posit8Target::qaFms(Number a, Number b) {
        Posit8 pa = bits_to_posit<Posit8>(a.bits);
        Posit8 pb = bits_to_posit<Posit8>(b.bits);
        *reinterpret_cast<Quire8*>(quire) -= sw::universal::quire_mul(pa, pb);
    }

    void Posit8Target::qaNeg() {
        Quire8& q = *reinterpret_cast<Quire8*>(quire);
        if (!q.iszero()) q.set_sign(!q.sign());
    }

    Number Posit8Target::qaRead() {
        Quire8& q = *reinterpret_cast<Quire8*>(quire);
        return Number{posit_to_bits(sw::universal::quire_resolve(q))};
    }
}