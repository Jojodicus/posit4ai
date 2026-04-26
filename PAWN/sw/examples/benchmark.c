/*
 * benchmark.c -- PAWN throughput benchmark
 *
 * Measures cycles-per-operation by timing a long sequence of a single opcode.
 * Reports raw elapsed time and effective cycles/op at the configured clock.
 *
 * Usage:
 *   ./benchmark [N]   (N = number of ADD ops, default 1000)
 *
 * DBRAM layout:
 *   [0]        operand a  (posit 1.0)
 *   [1]        operand b  (posit 1.0)
 *   [2..N+1]   results (one per ADD; all independent, no RAW hazard)
 *
 * Steady-state throughput applies (no RAW -> no forwarding stalls).
 */

#include "../pawn.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Must match the CLOCK_FREQ_MHZ used at ./impl.sh time */
#ifndef CLOCK_FREQ_MHZ
#define CLOCK_FREQ_MHZ 30
#endif

static int load_and_run(pawn_dev_t *dev, const uint64_t *prog, int N,
                         long long *ns_out)
{
    pawn_reset(dev);

    uint32_t vals[2] = { 0x40000000, 0x40000000 }; /* posit<32,2> 1.0 */
    pawn_dbram_write(dev, 0, vals, 2);

    if (pawn_load_program(dev, prog, N + 1) != 0)
        return -1;

    long long ns = pawn_run_blocking(dev, 5000);
    if (ns < 0) return -1;
    *ns_out = ns;
    return 0;
}

int main(int argc, char *argv[])
{
    int N = 1000;
    if (argc > 1)
        N = atoi(argv[1]);
    if (N < 1 || N > (1 << 15) - 3) {
        fprintf(stderr, "N must be in [1, %d]\n", (1 << 15) - 3);
        return 1;
    }

    uint64_t *prog = (uint64_t *)malloc((N + 1) * sizeof(uint64_t));
    if (!prog) { perror("malloc"); return 1; }

    for (int i = 0; i < N; i++)
        prog[i] = PAWN_INSTR(PAWN_OP_ADD, 0, 1, i + 2);
    prog[N] = PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0);

    pawn_dev_t dev;
    if (pawn_open(&dev) != 0) { free(prog); return 1; }

    long long ns = 0;

    /* warm-up run (MMCM/AXI bus may have cold-start overhead) */
    if (load_and_run(&dev, prog, N, &ns) != 0) {
        pawn_close(&dev); free(prog); return 1;
    }

    /* measured run */
    if (load_and_run(&dev, prog, N, &ns) != 0) {
        pawn_close(&dev); free(prog); return 1;
    }

    free(prog);

    double clk_period_ns = 1000.0 / CLOCK_FREQ_MHZ;
    double cycles        = (double)ns / clk_period_ns;
    double cycles_per_op = cycles / N;
    double ops_per_sec   = (double)N / ((double)ns * 1e-9);

    printf("Ops:          %d ADD\n", N);
    printf("Elapsed:      %.3f us\n", ns / 1000.0);
    printf("Ops/sec:      %.3e\n", ops_per_sec);
    printf("Cycles total: %.0f  (at %d MHz assumed)\n", cycles, CLOCK_FREQ_MHZ);
    printf("Cycles/op:    %.2f\n", cycles_per_op);

    pawn_close(&dev);
    return 0;
}
