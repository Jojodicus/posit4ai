/*
 * hello_posit.c -- minimal PAWN smoke test (posit32 / DATA_WIDTH=32)
 *
 * Computes c[i] = a[i] + b[i] for N values, reads results back.
 *
 * Change pawn_dbram_write32/read32 -> pawn_dbram_write8/read8 (etc.) and
 * the data arrays to use the appropriate upper-bits encoding for other widths.
 * posit 1.0 is 0x40000000 for DATA_WIDTH 8, 16, and 32 (same upper bits).
 *
 * DBRAM layout:  [0..N-1] a   [N..2N-1] b   [2N..3N-1] c (results)
 */

#include "../pawn.h"
#include <stdio.h>

#define N 4

int main(void)
{
    printf("hello!\n");
    pawn_dev_t dev;
    if (pawn_open(&dev) != 0)
        return 1;
    printf("opened pawn\n");

    pawn_reset(&dev);
    printf("reset pawn\n");

    /* posit<32,2>: 1.0=0x40000000  2.0=0x48000000  3.0=0x4C000000  4.0=0x50000000 */
    uint32_t a[N] = { 0x40000000, 0x48000000, 0x4C000000, 0x50000000 };
    uint32_t b[N] = { 0x40000000, 0x40000000, 0x40000000, 0x40000000 }; /* 1.0 */
    uint32_t c[N] = { 0 };
    /* expected: c = { 2.0, 3.0, 4.0, 5.0 } */

    pawn_dbram_write32(&dev, 0, a, N);
    printf("wrote a\n");
    pawn_dbram_write32(&dev, N, b, N);
    printf("wrote b\n");

    uint64_t prog[N + 1];
    for (int i = 0; i < N; i++)
        prog[i] = PAWN_INSTR(PAWN_OP_ADD, i, N + i, 2*N + i);
    prog[N] = PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0);

    pawn_load_program(&dev, prog, N + 1);
    printf("program loaded\n");

    long long ns = pawn_run_blocking(&dev, 1000);
    printf("ran program\n");
    if (ns < 0) { pawn_close(&dev); return 1; }

    pawn_dbram_read32(&dev, 2*N, c, N);
    printf("read results\n");

    printf("elapsed: %lld ns\n", ns);
    printf("%-4s  %-12s  %-12s  %-12s\n", "i", "a", "b", "c");
    for (int i = 0; i < N; i++)
        printf("%-4d  0x%08X    0x%08X    0x%08X\n", i, a[i], b[i], c[i]);

    pawn_close(&dev);
    printf("closed pawn, bye!\n");
    return 0;
}
