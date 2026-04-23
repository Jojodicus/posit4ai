#include "libpawn.hpp"
#include <cmath>
#include <sstream>
#include <string>

#ifdef __riscv_xposit
#include "xposit_asm.h"
#include <universal/number/posit/posit.hpp>

namespace p
{
    using Xposit64 = sw::universal::posit<64, 2>;

    static inline uint64_t p64_to_u64(const Xposit64& p) {
        return p.bits().to_ull();
    }

    static inline Xposit64 u64_to_p64(uint64_t bits) {
        Xposit64 p;
        p.setbits(bits);
        return p;
    }
}
#endif

namespace p
{
    XpositTarget::XpositTarget() : Target(64, POSIT) {}

    Number XpositTarget::toNumber(float f) {
#ifdef __riscv_xposit
        return Number{p64_to_u64(Xposit64(f))};
#else
        uint32_t bits = std::bit_cast<uint32_t>(f);
        return Number{static_cast<uint64_t>(bits)};
#endif
    }

    Number XpositTarget::toNumber(double d) {
#ifdef __riscv_xposit
        return Number{p64_to_u64(Xposit64(d))};
#else
        return Number{std::bit_cast<uint64_t>(d)};
#endif
    }

    Number XpositTarget::toNumber(int32_t i) {
#ifdef __riscv_xposit
        return Number{xposit_from_i32(i)};
#else
        return Number{static_cast<uint64_t>(i)};
#endif
    }

    Number XpositTarget::toNumber(uint32_t i) {
#ifdef __riscv_xposit
        return Number{xposit_from_u32(i)};
#else
        return Number{static_cast<uint64_t>(i)};
#endif
    }

    Number XpositTarget::toNumber(int64_t i) {
#ifdef __riscv_xposit
        return Number{xposit_from_i64(i)};
#else
        return Number{static_cast<uint64_t>(i)};
#endif
    }

    Number XpositTarget::toNumber(uint64_t i) {
#ifdef __riscv_xposit
        return Number{xposit_from_u64(i)};
#else
        return Number{i};
#endif
    }

    float XpositTarget::toFloat(Number n) {
#ifdef __riscv_xposit
        return u64_to_p64(n.bits).operator float();
#else
        return std::bit_cast<float>(static_cast<uint32_t>(n.bits));
#endif
    }

    double XpositTarget::toDouble(Number n) {
#ifdef __riscv_xposit
        return u64_to_p64(n.bits).operator double();
#else
        return std::bit_cast<double>(n.bits);
#endif
    }

    int32_t XpositTarget::toInt32(Number n) {
#ifdef __riscv_xposit
        return xposit_to_i32(n.bits);
#else
        return static_cast<int32_t>(n.bits);
#endif
    }

    uint32_t XpositTarget::toUint32(Number n) {
#ifdef __riscv_xposit
        return xposit_to_u32(n.bits);
#else
        return static_cast<uint32_t>(n.bits);
#endif
    }

    int64_t XpositTarget::toInt64(Number n) {
#ifdef __riscv_xposit
        return xposit_to_i64(n.bits);
#else
        return static_cast<int64_t>(n.bits);
#endif
    }

    uint64_t XpositTarget::toUint64(Number n) {
#ifdef __riscv_xposit
        return xposit_to_u64(n.bits);
#else
        return n.bits;
#endif
    }

    std::string XpositTarget::toString(Number n) {
        std::ostringstream oss;
        oss << std::hex << n.bits;
        return oss.str();
    }

    Number XpositTarget::add(Number a, Number b) {
#ifdef __riscv_xposit
        return Number{xposit_add(a.bits, b.bits)};
#else
        return Number{0};
#endif
    }

    Number XpositTarget::sub(Number a, Number b) {
#ifdef __riscv_xposit
        return Number{xposit_sub(a.bits, b.bits)};
#else
        return Number{0};
#endif
    }

    Number XpositTarget::mul(Number a, Number b) {
#ifdef __riscv_xposit
        return Number{xposit_mul(a.bits, b.bits)};
#else
        return Number{0};
#endif
    }

    Number XpositTarget::div(Number a, Number b) {
#ifdef __riscv_xposit
        return Number{xposit_div(a.bits, b.bits)};
#else
        return Number{0};
#endif
    }

    Number XpositTarget::neg(Number a) {
#ifdef __riscv_xposit
        return Number{xposit_neg(a.bits)};
#else
        return Number{0};
#endif
    }

    Number XpositTarget::abs(Number a) {
#ifdef __riscv_xposit
        return Number{xposit_abs(a.bits)};
#else
        return Number{0};
#endif
    }

    Number XpositTarget::sqrt(Number a) {
#ifdef __riscv_xposit
        return Number{xposit_sqrt(a.bits)};
#else
        return Number{0};
#endif
    }

    Number XpositTarget::relu(Number a) {
        return (a.bits & 0x8000000000000000ULL) ? Number{0} : a;
    }

    void XpositTarget::qaClear() {
#ifdef __riscv_xposit
        xposit_quire_clear();
#endif
    }

    void XpositTarget::qaAdd(Number a) {
#ifdef __riscv_xposit
        xposit_quire_add(a.bits);
#endif
    }

    void XpositTarget::qaFma(Number a, Number b) {
#ifdef __riscv_xposit
        xposit_quire_add_mul(a.bits, b.bits);
#endif
    }

    void XpositTarget::qaFms(Number a, Number b) {
#ifdef __riscv_xposit
        xposit_quire_add_sub_mul(a.bits, b.bits);
#endif
    }

    void XpositTarget::qaNeg() {
#ifdef __riscv_xposit
        xposit_quire_neg();
#endif
    }

    Number XpositTarget::qaRead() {
#ifdef __riscv_xposit
        return Number{xposit_quire_read()};
#else
        return Number{0};
#endif
    }
}