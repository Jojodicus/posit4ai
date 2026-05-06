/*
 * hello_posit2.c -- second PAWN smoke test (posit32 / DATA_WIDTH=32)
 *
 * Computes c[i] = a[i] * b[i] for N values (MUL instead of ADD).
 *
 * DBRAM layout:  [0..N-1] a   [N..2N-1] b   [2N..3N-1] c (results)
 */

#include "../pawn.h"
#include <stdio.h>

#define N 4

static int verify_dbram32(pawn_dev_t *dev, uint32_t base, const uint32_t *exp, size_t n, const char *tag)
{
    int ok = 1;
    for (size_t i = 0; i < n; i++) {
        uint32_t got = pawn_dbram_peek32(dev, base + (uint32_t)i);
        if (got != exp[i]) {
            if (ok)
                printf("verify %s: FAIL\n", tag);
            printf("  [%zu] exp=0x%08X got=0x%08X\n", i, exp[i], got);
            ok = 0;
        }
    }
    if (ok)
        printf("verify %s: OK\n", tag);
    return ok;
}

int main(void)
{
    printf("hello_posit2 (MUL test)!\n");
    pawn_dev_t dev;
    if (pawn_open(&dev) != 0)
        return 1;
    printf("opened pawn\n");

    pawn_reset(&dev);
    printf("reset pawn\n");

    /* posit<32,2>: 1.0=0x40000000  2.0=0x48000000  3.0=0x4C000000  4.0=0x50000000
       0.5=0x38000000 */
    uint32_t a[N] = { 0x40000000, 0x48000000, 0x4C000000, 0x50000000 }; /* 1,2,3,4 */
    uint32_t b[N] = { 0x40000000, 0x40000000, 0x40000000, 0x38000000 }; /* 1,1,1,0.5 */
    uint32_t c[N] = { 0 };
    /* expected: c = { 1*1, 2*1, 3*1, 4*0.5 } = { 1, 2, 3, 2 } */
    uint32_t exp[N] = { 0x40000000, 0x48000000, 0x4C000000, 0x48000000 };

    pawn_dbram_write32(&dev, 0, a, N);
    printf("wrote a\n");
    pawn_dbram_write32(&dev, N, b, N);
    printf("wrote b\n");

    verify_dbram32(&dev, 0, a, N, "a");
    verify_dbram32(&dev, N, b, N, "b");

    uint64_t prog[N + 1];
    for (int i = 0; i < N; i++)
        prog[i] = PAWN_INSTR(PAWN_OP_MUL, i, N + i, 2*N + i);
    prog[N] = PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0);

    pawn_load_program(&dev, prog, N + 1);
    printf("program loaded (MUL)\n");

    long long ns = pawn_run_blocking(&dev, 1000);
    printf("ran program\n");
    if (ns < 0) { pawn_close(&dev); return 1; }

    pawn_dbram_read32(&dev, 2*N, c, N);
    printf("read results\n");

    printf("elapsed: %lld ns\n", ns);
    verify_dbram32(&dev, 2*N, exp, N, "result");
    printf("%-4s  %-12s  %-12s  %-12s\n", "i", "a", "b", "c");
    for (int i = 0; i < N; i++)
        printf("%-4d  0x%08X    0x%08X    0x%08X\n", i, a[i], b[i], c[i]);

    pawn_close(&dev);
    printf("closed pawn, bye!\n");
    return 0;
}
