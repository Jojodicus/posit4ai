#include "libpawn.hpp"
#include "universal.hpp"
#include <cmath>

namespace p
{
    Posit64Target::Posit64Target() : UniversalTarget(64) {
        quire = new Quire64();
    }

    Number Posit64Target::toNumber(float f) {
        return toNumber(static_cast<double>(f));
    }

    Number Posit64Target::toNumber(double d) {
        Posit64 p(d);
        return Number{posit_to_bits(p)};
    }

    Number Posit64Target::toNumber(int32_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit64Target::toNumber(uint32_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit64Target::toNumber(int64_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit64Target::toNumber(uint64_t i) {
        return toNumber(static_cast<double>(i));
    }

    float Posit64Target::toFloat(Number n) {
        return static_cast<float>(bits_to_posit<Posit64>(n.bits).operator double());
    }

    double Posit64Target::toDouble(Number n) {
        return bits_to_posit<Posit64>(n.bits).operator double();
    }

    int32_t Posit64Target::toInt32(Number n) {
        return static_cast<int32_t>(bits_to_posit<Posit64>(n.bits).operator int64_t());
    }

    uint32_t Posit64Target::toUint32(Number n) {
        double d = bits_to_posit<Posit64>(n.bits).operator double();
        if (d < 0) return 0;
        if (d > UINT32_MAX) return UINT32_MAX;
        return static_cast<uint32_t>(d);
    }

    int64_t Posit64Target::toInt64(Number n) {
        return bits_to_posit<Posit64>(n.bits).operator int64_t();
    }

    uint64_t Posit64Target::toUint64(Number n) {
        double d = bits_to_posit<Posit64>(n.bits).operator double();
        if (d < 0) return 0;
        if (d > UINT64_MAX) return UINT64_MAX;
        return static_cast<uint64_t>(d);
    }

    std::string Posit64Target::toString(Number n) {
        return std::to_string(bits_to_posit<Posit64>(n.bits).operator double());
    }

    Number Posit64Target::add(Number a, Number b) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        Posit64 pb = bits_to_posit<Posit64>(b.bits);
        return Number{posit_to_bits(pa + pb)};
    }

    Number Posit64Target::sub(Number a, Number b) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        Posit64 pb = bits_to_posit<Posit64>(b.bits);
        return Number{posit_to_bits(pa - pb)};
    }

    Number Posit64Target::mul(Number a, Number b) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        Posit64 pb = bits_to_posit<Posit64>(b.bits);
        return Number{posit_to_bits(pa * pb)};
    }

    Number Posit64Target::div(Number a, Number b) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        Posit64 pb = bits_to_posit<Posit64>(b.bits);
        return Number{posit_to_bits(pa / pb)};
    }

    Number Posit64Target::neg(Number a) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        return Number{posit_to_bits(-pa)};
    }

    Number Posit64Target::abs(Number a) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        double d = pa.operator double();
        if (d < 0) d = -d;
        return Number{posit_to_bits(Posit64(d))};
    }

    Number Posit64Target::sqrt(Number a) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        return Number{posit_to_bits(sw::universal::sqrt(pa))};
    }

    Number Posit64Target::relu(Number a) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        double d = pa.operator double();
        return Number{(d < 0 ? Posit64(0.0) : pa).bits().to_ull()};
    }

    void Posit64Target::qaClear() {
        reinterpret_cast<Quire64*>(quire)->clear();
    }

    void Posit64Target::qaAdd(Number a) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        *reinterpret_cast<Quire64*>(quire) += sw::universal::quire_mul(pa, Posit64(1.0));
    }

    void Posit64Target::qaFma(Number a, Number b) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        Posit64 pb = bits_to_posit<Posit64>(b.bits);
        *reinterpret_cast<Quire64*>(quire) += sw::universal::quire_mul(pa, pb);
    }

    void Posit64Target::qaFms(Number a, Number b) {
        Posit64 pa = bits_to_posit<Posit64>(a.bits);
        Posit64 pb = bits_to_posit<Posit64>(b.bits);
        *reinterpret_cast<Quire64*>(quire) -= sw::universal::quire_mul(pa, pb);
    }

    void Posit64Target::qaNeg() {
        Quire64& q = *reinterpret_cast<Quire64*>(quire);
        if (!q.iszero()) q.set_sign(!q.sign());
    }

    Number Posit64Target::qaRead() {
        Quire64& q = *reinterpret_cast<Quire64*>(quire);
        return Number{posit_to_bits(sw::universal::quire_resolve(q))};
    }
}