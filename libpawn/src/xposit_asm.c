#include <stdint.h>
#include "xposit_asm.h"

uint64_t xposit_add(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pld    pt1,0(%3)     \n"
        "padd.s pt2,pt0,pt1   \n"
        "psd    pt2,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a), "r"(&b)
    );
    return r;
}

uint64_t xposit_sub(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pld    pt1,0(%3)     \n"
        "psub.s pt2,pt0,pt1   \n"
        "psd    pt2,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a), "r"(&b)
    );
    return r;
}

uint64_t xposit_mul(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pld    pt1,0(%3)     \n"
        "pmul.s pt2,pt0,pt1   \n"
        "psd    pt2,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a), "r"(&b)
    );
    return r;
}

uint64_t xposit_div(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pld    pt1,0(%3)     \n"
        "pdiv.s pt2,pt0,pt1   \n"
        "psd    pt2,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a), "r"(&b)
    );
    return r;
}

uint64_t xposit_sqrt(uint64_t a) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "psqrt.s pt1,pt0      \n"
        "psd    pt1,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a)
    );
    return r;
}

uint64_t xposit_neg(uint64_t a) {
    return xposit_sub(0ULL, a);
}

uint64_t xposit_abs(uint64_t a) {
    return (a & 0x8000000000000000ULL) ? xposit_neg(a) : a;
}

uint64_t xposit_eq(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pld    pt1,0(%3)     \n"
        "peq.s  t0,pt0,pt1    \n"
        "sd     t0,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a), "r"(&b)
    );
    return r;
}

uint64_t xposit_lt(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pld    pt1,0(%3)     \n"
        "plt.s  t0,pt0,pt1    \n"
        "sd     t0,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a), "r"(&b)
    );
    return r;
}

uint64_t xposit_le(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pld    pt1,0(%3)     \n"
        "ple.s  t0,pt0,pt1    \n"
        "sd     t0,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a), "r"(&b)
    );
    return r;
}

int32_t xposit_to_i32(uint64_t a) {
    int32_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pcvt.w.s t1,pt0      \n"
        "sw     t1,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a)
        : "t1"
    );
    return r;
}

uint32_t xposit_to_u32(uint64_t a) {
    uint32_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pcvt.wu.s t1,pt0      \n"
        "sw     t1,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a)
        : "t1"
    );
    return r;
}

int64_t xposit_to_i64(uint64_t a) {
    int64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pcvt.l.s t1,pt0       \n"
        "sd     t1,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a)
        : "t1"
    );
    return r;
}

uint64_t xposit_to_u64(uint64_t a) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%2)     \n"
        "pcvt.lu.s t1,pt0      \n"
        "sd     t1,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a)
        : "t1"
    );
    return r;
}

uint64_t xposit_from_i32(int32_t a) {
    uint64_t r;
    __asm__ __volatile__(
        "lw     t1,0(%2)     \n"
        "pcvt.s.w pt0,t1       \n"
        "psd    pt0,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a)
        : "t1"
    );
    return r;
}

uint64_t xposit_from_u32(uint32_t a) {
    uint64_t r;
    __asm__ __volatile__(
        "lw     t1,0(%2)     \n"
        "pcvt.s.wu pt0,t1     \n"
        "psd    pt0,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a)
        : "t1"
    );
    return r;
}

uint64_t xposit_from_i64(int64_t a) {
    uint64_t r;
    __asm__ __volatile__(
        "ld     t1,0(%2)     \n"
        "pcvt.s.l pt0,t1       \n"
        "psd    pt0,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a)
        : "t1"
    );
    return r;
}

uint64_t xposit_from_u64(uint64_t a) {
    uint64_t r;
    __asm__ __volatile__(
        "ld     t1,0(%2)     \n"
        "pcvt.s.lu pt0,t1      \n"
        "psd    pt0,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r), "r"(&a)
        : "t1"
    );
    return r;
}

void xposit_quire_clear(void) {
    __asm__ __volatile__("qclr.s" ::: "memory");
}

void xposit_quire_add(uint64_t a) {
    static const uint64_t posit_one = 0x4000000000000000ULL;
    __asm__ __volatile__(
        "pld    pt0,0(%0)     \n"
        "pld    pt1,0(%1)     \n"
        "qmadd.s pt0,pt1      \n"
        :
        : "r"(&posit_one), "r"(&a)
    );
}

void xposit_quire_add_mul(uint64_t a, uint64_t b) {
    __asm__ __volatile__(
        "pld    pt0,0(%0)     \n"
        "pld    pt1,0(%1)     \n"
        "qmadd.s pt0,pt1      \n"
        :
        : "r"(&a), "r"(&b)
    );
}

void xposit_quire_add_sub_mul(uint64_t a, uint64_t b) {
    __asm__ __volatile__(
        "pld    pt0,0(%0)     \n"
        "pld    pt1,0(%1)     \n"
        "qmsub.s pt0,pt1      \n"
        :
        : "r"(&a), "r"(&b)
    );
}

void xposit_quire_neg(void) {
    __asm__ __volatile__("qneg.s" ::: "memory");
}

uint64_t xposit_quire_read(void) {
    uint64_t r;
    __asm__ __volatile__(
        "qround.s pt0        \n"
        "psd    pt0,0(%1)     \n"
        : "=rm"(r)
        : "r"(&r)
    );
    return r;
}