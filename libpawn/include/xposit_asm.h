#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t xposit_add(uint64_t a, uint64_t b);
uint64_t xposit_sub(uint64_t a, uint64_t b);
uint64_t xposit_mul(uint64_t a, uint64_t b);
uint64_t xposit_div(uint64_t a, uint64_t b);
uint64_t xposit_sqrt(uint64_t a);
uint64_t xposit_neg(uint64_t a);
uint64_t xposit_abs(uint64_t a);

uint64_t xposit_eq(uint64_t a, uint64_t b);
uint64_t xposit_lt(uint64_t a, uint64_t b);
uint64_t xposit_le(uint64_t a, uint64_t b);

int32_t xposit_to_i32(uint64_t a);
uint32_t xposit_to_u32(uint64_t a);
int64_t xposit_to_i64(uint64_t a);
uint64_t xposit_to_u64(uint64_t a);

uint64_t xposit_from_i32(int32_t a);
uint64_t xposit_from_u32(uint32_t a);
uint64_t xposit_from_i64(int64_t a);
uint64_t xposit_from_u64(uint64_t a);

void xposit_quire_clear(void);
void xposit_quire_add(uint64_t a);
void xposit_quire_add_mul(uint64_t a, uint64_t b);
void xposit_quire_add_sub_mul(uint64_t a, uint64_t b);
void xposit_quire_neg(void);
uint64_t xposit_quire_read(void);

#ifdef __cplusplus
}
#endif