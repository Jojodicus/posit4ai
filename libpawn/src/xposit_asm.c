#include <stdint.h>

/* xposit inline asm wrapper.
 * Compile with xposit clang: clang -march=rv64gcxposit ...
 */

uint64_t xposit_add(uint64_t a, uint64_t b);
uint64_t xposit_sub(uint64_t a, uint64_t b);
uint64_t xposit_mul(uint64_t a, uint64_t b);
uint64_t xposit_div(uint64_t a, uint64_t b);
uint64_t xposit_sqrt(uint64_t a);
uint64_t xposit_neg(uint64_t a);
uint64_t xposit_abs(uint64_t a);

void xposit_quire_clear(void);
void xposit_quire_add(uint64_t a);
void xposit_quire_add_mul(uint64_t a, uint64_t b);
void xposit_quire_add_sub_mul(uint64_t a, uint64_t b);
void xposit_quire_neg(void);
uint64_t xposit_quire_read(void);

uint64_t xposit_add(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%1)     \n"
        "pld    pt1,0(%2)     \n"
        "padd.s pt2,pt0,pt1   \n"
        "psd    pt2,0(%0)     \n"
        : "=r"(r)
        : "r"(&a), "r"(&b)
    );
    return r;
}

uint64_t xposit_sub(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%1)     \n"
        "pld    pt1,0(%2)     \n"
        "psub.s pt2,pt0,pt1   \n"
        "psd    pt2,0(%0)     \n"
        : "=r"(r)
        : "r"(&a), "r"(&b)
    );
    return r;
}

uint64_t xposit_mul(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%1)     \n"
        "pld    pt1,0(%2)     \n"
        "pmul.s pt2,pt0,pt1   \n"
        "psd    pt2,0(%0)     \n"
        : "=r"(r)
        : "r"(&a), "r"(&b)
    );
    return r;
}

uint64_t xposit_div(uint64_t a, uint64_t b) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%1)     \n"
        "pld    pt1,0(%2)     \n"
        "pdiv.s pt2,pt0,pt1   \n"
        "psd    pt2,0(%0)     \n"
        : "=r"(r)
        : "r"(&a), "r"(&b)
    );
    return r;
}

uint64_t xposit_sqrt(uint64_t a) {
    uint64_t r;
    __asm__ __volatile__(
        "pld    pt0,0(%1)     \n"
        "psqrt.s pt1,pt0      \n"
        "psd    pt1,0(%0)     \n"
        : "=r"(r)
        : "r"(&a)
    );
    return r;
}

uint64_t xposit_neg(uint64_t a) {
    return xposit_sub(0, a);
}

uint64_t xposit_abs(uint64_t a) {
    return (a & 0x8000000000000000ULL) ? xposit_neg(a) : a;
}

/* Quire operations - stubbed for now */
void xposit_quire_clear(void) { }
void xposit_quire_add(uint64_t a) { (void)a; }
void xposit_quire_add_mul(uint64_t a, uint64_t b) { (void)a; (void)b; }
void xposit_quire_add_sub_mul(uint64_t a, uint64_t b) { (void)a; (void)b; }
void xposit_quire_neg(void) { }
uint64_t xposit_quire_read(void) { return 0; }