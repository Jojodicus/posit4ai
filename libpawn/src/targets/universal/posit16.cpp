#include "libpawn.hpp"
#include "universal.hpp"
#include <cmath>

namespace p
{
    Posit16Target::Posit16Target() : UniversalTarget(16) {
        quire = new Quire16();
    }

    Number Posit16Target::toNumber(float f) {
        return toNumber(static_cast<double>(f));
    }

    Number Posit16Target::toNumber(double d) {
        Posit16 p(d);
        return Number{posit_to_bits(p)};
    }

    Number Posit16Target::toNumber(int32_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit16Target::toNumber(uint32_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit16Target::toNumber(int64_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit16Target::toNumber(uint64_t i) {
        return toNumber(static_cast<double>(i));
    }

    float Posit16Target::toFloat(Number n) {
        return static_cast<float>(bits_to_posit<Posit16>(n.bits).operator double());
    }

    double Posit16Target::toDouble(Number n) {
        return bits_to_posit<Posit16>(n.bits).operator double();
    }

    int32_t Posit16Target::toInt32(Number n) {
        return static_cast<int32_t>(bits_to_posit<Posit16>(n.bits).operator int64_t());
    }

    uint32_t Posit16Target::toUint32(Number n) {
        double d = bits_to_posit<Posit16>(n.bits).operator double();
        if (d < 0) return 0;
        if (d > UINT32_MAX) return UINT32_MAX;
        return static_cast<uint32_t>(d);
    }

    int64_t Posit16Target::toInt64(Number n) {
        return bits_to_posit<Posit16>(n.bits).operator int64_t();
    }

    uint64_t Posit16Target::toUint64(Number n) {
        double d = bits_to_posit<Posit16>(n.bits).operator double();
        if (d < 0) return 0;
        if (d > UINT64_MAX) return UINT64_MAX;
        return static_cast<uint64_t>(d);
    }

    std::string Posit16Target::toString(Number n) {
        return std::to_string(bits_to_posit<Posit16>(n.bits).operator double());
    }

    Number Posit16Target::add(Number a, Number b) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        Posit16 pb = bits_to_posit<Posit16>(b.bits);
        return Number{posit_to_bits(pa + pb)};
    }

    Number Posit16Target::sub(Number a, Number b) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        Posit16 pb = bits_to_posit<Posit16>(b.bits);
        return Number{posit_to_bits(pa - pb)};
    }

    Number Posit16Target::mul(Number a, Number b) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        Posit16 pb = bits_to_posit<Posit16>(b.bits);
        return Number{posit_to_bits(pa * pb)};
    }

    Number Posit16Target::div(Number a, Number b) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        Posit16 pb = bits_to_posit<Posit16>(b.bits);
        return Number{posit_to_bits(pa / pb)};
    }

    Number Posit16Target::neg(Number a) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        return Number{posit_to_bits(-pa)};
    }

    Number Posit16Target::abs(Number a) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        double d = pa.operator double();
        if (d < 0) d = -d;
        return Number{posit_to_bits(Posit16(d))};
    }

    Number Posit16Target::sqrt(Number a) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        return Number{posit_to_bits(sw::universal::sqrt(pa))};
    }

    Number Posit16Target::relu(Number a) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        double d = pa.operator double();
        return Number{(d < 0 ? Posit16(0.0) : pa).bits().to_ull()};
    }

    void Posit16Target::qaClear() {
        reinterpret_cast<Quire16*>(quire)->clear();
    }

    void Posit16Target::qaAdd(Number a) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        *reinterpret_cast<Quire16*>(quire) += sw::universal::quire_mul(pa, Posit16(1.0));
    }

    void Posit16Target::qaFma(Number a, Number b) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        Posit16 pb = bits_to_posit<Posit16>(b.bits);
        *reinterpret_cast<Quire16*>(quire) += sw::universal::quire_mul(pa, pb);
    }

    void Posit16Target::qaFms(Number a, Number b) {
        Posit16 pa = bits_to_posit<Posit16>(a.bits);
        Posit16 pb = bits_to_posit<Posit16>(b.bits);
        *reinterpret_cast<Quire16*>(quire) -= sw::universal::quire_mul(pa, pb);
    }

    void Posit16Target::qaNeg() {
        Quire16& q = *reinterpret_cast<Quire16*>(quire);
        if (!q.iszero()) q.set_sign(!q.sign());
    }

    Number Posit16Target::qaRead() {
        Quire16& q = *reinterpret_cast<Quire16*>(quire);
        return Number{posit_to_bits(sw::universal::quire_resolve(q))};
    }
}