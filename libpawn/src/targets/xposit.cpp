#include "libpawn.hpp"
#include "xposit_asm.h"

#include <sw/universal/number/posit/posit.hpp>
#include <bit>
#include <sstream>
#include <string>

namespace p
{
    using Xposit64 = sw::universal::posit<64, 2>;

    XpositTarget::XpositTarget() : Target(64, POSIT) {}

    Number XpositTarget::toNumber(float f) {
        Xposit64 p = f;
        return Number{p.bits().to_ull()};
    }

    Number XpositTarget::toNumber(double d) {
        Xposit64 p = d;
        return Number{p.bits().to_ull()};
    }

    Number XpositTarget::toNumber(int32_t i) {
        return Number{xposit_from_i32(i)};
    }

    Number XpositTarget::toNumber(uint32_t i) {
        return Number{xposit_from_u32(i)};
    }

    Number XpositTarget::toNumber(int64_t i) {
        return Number{xposit_from_i64(i)};
    }

    Number XpositTarget::toNumber(uint64_t i) {
        return Number{xposit_from_u64(i)};
    }

    float XpositTarget::toFloat(Number n) {
        Xposit64 p(n.bits);
        return p.operator float();
    }

    double XpositTarget::toDouble(Number n) {
        Xposit64 p(n.bits);
        return p.operator double();
    }

    int32_t XpositTarget::toInt32(Number n) {
        return xposit_to_i32(n.bits);
    }

    uint32_t XpositTarget::toUint32(Number n) {
        return xposit_to_u32(n.bits);
    }

    int64_t XpositTarget::toInt64(Number n) {
        return xposit_to_i64(n.bits);
    }

    uint64_t XpositTarget::toUint64(Number n) {
        return xposit_to_u64(n.bits);
    }

    std::string XpositTarget::toString(Number n) {
        std::ostringstream oss;
        oss << std::hex << n.bits;
        return oss.str();
    }

    Number XpositTarget::add(Number a, Number b) {
        return Number{xposit_add(a.bits, b.bits)};
    }

    Number XpositTarget::sub(Number a, Number b) {
        return Number{xposit_sub(a.bits, b.bits)};
    }

    Number XpositTarget::mul(Number a, Number b) {
        return Number{xposit_mul(a.bits, b.bits)};
    }

    Number XpositTarget::div(Number a, Number b) {
        return Number{xposit_div(a.bits, b.bits)};
    }

    Number XpositTarget::neg(Number a) {
        return Number{xposit_neg(a.bits)};
    }

    Number XpositTarget::abs(Number a) {
        return Number{xposit_abs(a.bits)};
    }

    Number XpositTarget::sqrt(Number a) {
        return Number{xposit_sqrt(a.bits)};
    }

    Number XpositTarget::relu(Number a) {
        return (a.bits & 0x8000000000000000ULL) ? Number{0} : a;
    }

    void XpositTarget::qaClear() {
        xposit_quire_clear();
    }

    void XpositTarget::qaAdd(Number a) {
        xposit_quire_add(a.bits);
    }

    void XpositTarget::qaFma(Number a, Number b) {
        xposit_quire_add_mul(a.bits, b.bits);
    }

    void XpositTarget::qaFms(Number a, Number b) {
        xposit_quire_add_sub_mul(a.bits, b.bits);
    }

    void XpositTarget::qaNeg() {
        xposit_quire_neg();
    }

    Number XpositTarget::qaRead() {
        return Number{xposit_quire_read()};
    }
}