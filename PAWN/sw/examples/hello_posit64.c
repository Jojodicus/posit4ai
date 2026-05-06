/*
 * hello_posit.c -- minimal PAWN smoke test (posit64 / DATA_WIDTH=64)
 *
 * Computes c[i] = a[i] + b[i] for N values, reads results back.
 *
 * DBRAM layout:  [0..N-1] a   [N..2N-1] b   [2N..3N-1] c (results)
 */

#include "../pawn.h"
#include <stdio.h>

#define N 4

static int verify_dbram64(pawn_dev_t *dev, uint32_t base, const uint64_t *exp, size_t n, const char *tag)
{
    int ok = 1;
    for (size_t i = 0; i < n; i++) {
        uint64_t got = pawn_dbram_peek64(dev, base + (uint32_t)i);
        if (got != exp[i]) {
            if (ok)
                printf("verify %s: FAIL\n", tag);
            printf("  [%zu] exp=0x%016llX got=0x%016llX\n", i,
                   (unsigned long long)exp[i],
                   (unsigned long long)got);
            ok = 0;
        }
    }
    if (ok)
        printf("verify %s: OK\n", tag);
    return ok;
}

int main(void)
{
    printf("hello!\n");
    pawn_dev_t dev;
    if (pawn_open(&dev) != 0)
        return 1;
    printf("opened pawn\n");

    pawn_reset(&dev);
    printf("reset pawn\n");

    /* posit<64,2>: 1.0=0x4000000000000000 2.0=0x4800000000000000 ... */
    uint64_t a[N] = { 0x4000000000000000ULL, 0x4800000000000000ULL, 0x4C00000000000000ULL, 0x5000000000000000ULL };
    uint64_t b[N] = { 0x4000000000000000ULL, 0x4000000000000000ULL, 0x4000000000000000ULL, 0x4000000000000000ULL }; /* 1.0 */
    uint64_t c[N] = { 0 };
    uint64_t exp[N] = { 0x4800000000000000ULL, 0x4C00000000000000ULL, 0x5000000000000000ULL, 0x5200000000000000ULL };
    /* expected: c = { 2.0, 3.0, 4.0, 5.0 } */

    for (int i = 0; i < N; i++)
        pawn_dbram_poke64(&dev, (uint32_t)i, a[i]);
    printf("wrote a\n");
    for (int i = 0; i < N; i++)
        pawn_dbram_poke64(&dev, (uint32_t)(N + i), b[i]);
    printf("wrote b\n");

    verify_dbram64(&dev, 0, a, N, "a");
    verify_dbram64(&dev, N, b, N, "b");

    uint64_t prog[N + 1];
    for (int i = 0; i < N; i++)
        prog[i] = PAWN_INSTR(PAWN_OP_ADD, i, N + i, 2*N + i);
    prog[N] = PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0);

    pawn_load_program(&dev, prog, N + 1);
    printf("program loaded\n");

    long long ns = pawn_run_blocking(&dev, 1000);
    printf("ran program\n");
    if (ns < 0) { pawn_close(&dev); return 1; }

    pawn_dbram_read64(&dev, 2*N, c, N);
    printf("read results\n");

    printf("elapsed: %lld ns\n", ns);
    verify_dbram64(&dev, 2*N, exp, N, "result");
    printf("%-4s  %-12s  %-12s  %-12s\n", "i", "a", "b", "c");
    for (int i = 0; i < N; i++)
        printf("%-4d  0x%016llX    0x%016llX    0x%016llX\n", i,
               (unsigned long long)a[i],
               (unsigned long long)b[i],
               (unsigned long long)c[i]);

    pawn_close(&dev);
    printf("closed pawn, bye!\n");
    return 0;
}
