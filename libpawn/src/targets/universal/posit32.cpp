#include "libpawn.hpp"
#include "universal.hpp"
#include <cmath>

namespace p
{
    Posit32Target::Posit32Target() : UniversalTarget(32) {
        quire = new Quire32();
    }

    Number Posit32Target::toNumber(float f) {
        return toNumber(static_cast<double>(f));
    }

    Number Posit32Target::toNumber(double d) {
        Posit32 p(d);
        return Number{posit_to_bits(p)};
    }

    Number Posit32Target::toNumber(int32_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit32Target::toNumber(uint32_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit32Target::toNumber(int64_t i) {
        return toNumber(static_cast<double>(i));
    }

    Number Posit32Target::toNumber(uint64_t i) {
        return toNumber(static_cast<double>(i));
    }

    float Posit32Target::toFloat(Number n) {
        return static_cast<float>(bits_to_posit<Posit32>(n.bits).operator double());
    }

    double Posit32Target::toDouble(Number n) {
        return bits_to_posit<Posit32>(n.bits).operator double();
    }

    int32_t Posit32Target::toInt32(Number n) {
        return static_cast<int32_t>(bits_to_posit<Posit32>(n.bits).operator int64_t());
    }

    uint32_t Posit32Target::toUint32(Number n) {
        double d = bits_to_posit<Posit32>(n.bits).operator double();
        if (d < 0) return 0;
        if (d > UINT32_MAX) return UINT32_MAX;
        return static_cast<uint32_t>(d);
    }

    int64_t Posit32Target::toInt64(Number n) {
        return bits_to_posit<Posit32>(n.bits).operator int64_t();
    }

    uint64_t Posit32Target::toUint64(Number n) {
        double d = bits_to_posit<Posit32>(n.bits).operator double();
        if (d < 0) return 0;
        if (d > UINT64_MAX) return UINT64_MAX;
        return static_cast<uint64_t>(d);
    }

    std::string Posit32Target::toString(Number n) {
        return std::to_string(bits_to_posit<Posit32>(n.bits).operator double());
    }

    Number Posit32Target::add(Number a, Number b) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        Posit32 pb = bits_to_posit<Posit32>(b.bits);
        return Number{posit_to_bits(pa + pb)};
    }

    Number Posit32Target::sub(Number a, Number b) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        Posit32 pb = bits_to_posit<Posit32>(b.bits);
        return Number{posit_to_bits(pa - pb)};
    }

    Number Posit32Target::mul(Number a, Number b) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        Posit32 pb = bits_to_posit<Posit32>(b.bits);
        return Number{posit_to_bits(pa * pb)};
    }

    Number Posit32Target::div(Number a, Number b) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        Posit32 pb = bits_to_posit<Posit32>(b.bits);
        return Number{posit_to_bits(pa / pb)};
    }

    Number Posit32Target::neg(Number a) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        return Number{posit_to_bits(-pa)};
    }

    Number Posit32Target::abs(Number a) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        double d = pa.operator double();
        if (d < 0) d = -d;
        return Number{posit_to_bits(Posit32(d))};
    }

    Number Posit32Target::sqrt(Number a) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        return Number{posit_to_bits(sw::universal::sqrt(pa))};
    }

    Number Posit32Target::relu(Number a) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        double d = pa.operator double();
        return Number{(d < 0 ? Posit32(0.0) : pa).bits().to_ull()};
    }

    void Posit32Target::qaClear() {
        reinterpret_cast<Quire32*>(quire)->clear();
    }

    void Posit32Target::qaAdd(Number a) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        *reinterpret_cast<Quire32*>(quire) += sw::universal::quire_mul(pa, Posit32(1.0));
    }

    void Posit32Target::qaFma(Number a, Number b) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        Posit32 pb = bits_to_posit<Posit32>(b.bits);
        *reinterpret_cast<Quire32*>(quire) += sw::universal::quire_mul(pa, pb);
    }

    void Posit32Target::qaFms(Number a, Number b) {
        Posit32 pa = bits_to_posit<Posit32>(a.bits);
        Posit32 pb = bits_to_posit<Posit32>(b.bits);
        *reinterpret_cast<Quire32*>(quire) -= sw::universal::quire_mul(pa, pb);
    }

    void Posit32Target::qaNeg() {
        Quire32& q = *reinterpret_cast<Quire32*>(quire);
        if (!q.iszero()) q.set_sign(!q.sign());
    }

    Number Posit32Target::qaRead() {
        Quire32& q = *reinterpret_cast<Quire32*>(quire);
        return Number{posit_to_bits(sw::universal::quire_resolve(q))};
    }
}