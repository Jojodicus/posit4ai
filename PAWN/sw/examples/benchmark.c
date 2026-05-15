/*
 * benchmark.c -- PAWN throughput benchmark (posit32 / DATA_WIDTH=32)
 *
 * Times N independent ADD operations (no RAW hazards -> steady-state throughput).
 * Reports elapsed time, ns/op, and MOPS.
 *
 * Usage: ./benchmark.elf [N]   (default N=1000)
 *
 * DBRAM layout:  [0] operand a (1.0)   [1] operand b (1.0)   [2..N+1] results
 */

#include "../pawn.h"
#include <stdio.h>
#include <stdlib.h>

static int run(pawn_dev_t *dev, const uint64_t *prog, int N, long long *ns_out)
{
    pawn_reset(dev);

    uint32_t vals[2] = { 0x40000000, 0x40000000 };
    pawn_dbram_write32(dev, 0, vals, 2);

    if (pawn_load_program(dev, prog, N + 1) != 0) return -1;

    long long ns = pawn_run_blocking(dev, 5000);
    if (ns < 0) return -1;
    *ns_out = ns;
    return 0;
}

int main(int argc, char *argv[])
{
    int N = 1000;
    if (argc > 1) N = atoi(argv[1]);
    if (N < 1 || N > (1 << 15) - 3) {
        fprintf(stderr, "N must be in [1, %d]\n", (1 << 15) - 3);
        return 1;
    }

    uint64_t *prog = malloc((N + 1) * sizeof(uint64_t));
    if (!prog) { perror("malloc"); return 1; }

    for (int i = 0; i < N; i++)
        prog[i] = PAWN_INSTR(PAWN_OP_ADD, 0, 1, i + 2);
    prog[N] = PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0);

    pawn_dev_t dev;
    if (pawn_open(&dev) != 0) { free(prog); return 1; }

    long long ns = 0;

    /* warm-up */
    if (run(&dev, prog, N, &ns) != 0) { pawn_close(&dev); free(prog); return 1; }
    /* measured */
    if (run(&dev, prog, N, &ns) != 0) { pawn_close(&dev); free(prog); return 1; }

    free(prog);

    double ns_per_op = (double)ns / N;
    double mops = (double)N / ((double)ns / 1e9) / 1e6;
    printf("N=%d  elapsed=%.3f us  ns/op=%.1f  MOPS=%.3f\n",
           N, ns / 1000.0, ns_per_op, mops);

    pawn_close(&dev);
    return 0;
}
