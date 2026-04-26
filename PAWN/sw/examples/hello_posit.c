/*
 * hello_posit.c -- minimal PAWN smoke test
 *
 * Computes:  c[i] = a[i] + b[i]  for N values, then reads results back.
 *
 * DBRAM layout:
 *   [0 .. N-1]     a[]
 *   [N .. 2N-1]    b[]
 *   [2N .. 3N-1]   c[]  (written by accelerator)
 *
 * Works for any ACCEL_TYPE (posit32 or float32 bit patterns differ, but
 * the raw hex passthrough below lets you verify the register interface).
 * For a posit32 smoke test, the values below are posit<32,2> encodings:
 *   1.0 = 0x40000000,  2.0 = 0x48000000,  3.0 = 0x4C000000
 */

#include "../pawn.h"
#include <stdio.h>
#include <string.h>

#define N 4

int main(void)
{
    pawn_dev_t dev;
    if (pawn_open(&dev) != 0)
        return 1;

    pawn_reset(&dev);

    /* posit<32,2> encodings */
    uint32_t a[N] = { 0x40000000, 0x48000000, 0x4C000000, 0x50000000 };
    /* b[i] = 1.0 for all */
    uint32_t b[N] = { 0x40000000, 0x40000000, 0x40000000, 0x40000000 };
    /* expected c[i] = a[i] + 1.0: 2.0, 3.0, 4.0, 5.0 */
    uint32_t c[N] = { 0 };

    /* Load operands into DBRAM via burst slave */
    pawn_dbram_write(&dev, 0,   a, N);
    pawn_dbram_write(&dev, N,   b, N);

    /* Program:
     *   for i in 0..N-1:  c[2N+i] = a[i] + b[i]
     *   HALT
     */
    uint64_t prog[N + 1];
    for (int i = 0; i < N; i++)
        prog[i] = PAWN_INSTR(PAWN_OP_ADD, i, N + i, 2*N + i);
    prog[N] = PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0);

    pawn_load_program(&dev, prog, N + 1);

    long long ns = pawn_run_blocking(&dev, 1000 /* ms timeout */);
    if (ns < 0) {
        pawn_close(&dev);
        return 1;
    }

    /* Read results back */
    pawn_dbram_read(&dev, 2*N, c, N);

    printf("elapsed: %lld ns\n", ns);
    printf("%-5s  %-12s  %-12s  %-12s\n", "i", "a (hex)", "b (hex)", "c (hex)");
    for (int i = 0; i < N; i++)
        printf("%-5d  0x%08X    0x%08X    0x%08X\n", i, a[i], b[i], c[i]);

    pawn_close(&dev);
    return 0;
}
