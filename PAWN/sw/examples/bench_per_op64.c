/*
 * bench_per_op64.c -- PAWN per-op throughput benchmark (64-bit)
 *
 * 64-bit counterpart of bench_per_op.c.  Same structure, but uses uint64_t
 * data arrays and pawn_dbram_write64/read64 for DBRAM access.
 *
 * Usage: ./bench_per_op64.elf [--count N] [--data-depth N] [--instr-depth N]
 */

#include "bench_common.h"

#define DATA_DEPTH_DEFAULT  32768
#define INSTR_DEPTH_DEFAULT 32768

typedef struct {
    const char *name;
    int         opcode;
    int         is_quire;
    int         n_src;
} OpInfo;

static const OpInfo OPS[] = {
    { "ADD",       PAWN_OP_ADD,       0, 2 },
    { "SUB",       PAWN_OP_SUB,       0, 2 },
    { "MUL",       PAWN_OP_MUL,       0, 2 },
    { "DIV",       PAWN_OP_DIV,       0, 2 },
    { "SQRT",      PAWN_OP_SQRT,      0, 1 },
    { "NEG",       PAWN_OP_NEG,       0, 1 },
    { "ABS",       PAWN_OP_ABS,       0, 1 },
    { "MOV",       PAWN_OP_MOV,       0, 1 },
    { "RELU",      PAWN_OP_RELU,      0, 1 },
    { "QACC_ADD",  PAWN_OP_QACC_ADD,  1, 1 },
    { "QACC_MADD", PAWN_OP_QACC_MADD, 1, 2 },
    { "QACC_MSUB", PAWN_OP_QACC_MSUB, 1, 2 },
    { "QACC_NEG",  PAWN_OP_QACC_NEG,  1, 0 },
};
#define NUM_OPS (sizeof(OPS) / sizeof(OPS[0]))

static size_t build_prog(uint64_t *prog, const OpInfo *op, int N)
{
    size_t n = 0;

    if (op->is_quire) {
        prog[n++] = PAWN_INSTR(PAWN_OP_QACC_CLEAR, 0, 0, 0);
        if (op->opcode == PAWN_OP_QACC_NEG)
            prog[n++] = PAWN_INSTR(PAWN_OP_QACC_ADD, 0, 0, 0);
        for (int i = 0; i < N; i++)
            prog[n++] = PAWN_INSTR(op->opcode,
                                   op->n_src >= 1 ? 0 : 0,
                                   op->n_src >= 2 ? 1 : 0, 0);
        prog[n++] = PAWN_INSTR(PAWN_OP_QACC_READ, 0, 0, 2);
    } else {
        int result_base = op->n_src;
        for (int i = 0; i < N; i++) {
            if (op->n_src == 2)
                prog[n++] = PAWN_INSTR(op->opcode, 0, 1, result_base + i);
            else
                prog[n++] = PAWN_INSTR(op->opcode, 0, 0, result_base + i);
        }
    }

    prog[n++] = PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0);
    return n;
}

static int max_n(const OpInfo *op, int data_depth, int instr_depth)
{
    if (op->is_quire) {
        int overhead = (op->opcode == PAWN_OP_QACC_NEG) ? 4 : 3;
        int max_instr = instr_depth - overhead;
        return max_instr > 0 ? max_instr : 0;
    }
    int result_base = op->n_src;
    int max_data = data_depth - result_base;
    return max_data > 0 ? max_data : 0;
}

int main(int argc, char *argv[])
{
    int data_depth  = DATA_DEPTH_DEFAULT;
    int instr_depth = INSTR_DEPTH_DEFAULT;
    int N           = 0;

    for (int i = 1; i < argc; i++) {
        if (i + 1 < argc && strcmp(argv[i], "--data-depth") == 0)
            data_depth = atoi(argv[++i]);
        else if (i + 1 < argc && strcmp(argv[i], "--instr-depth") == 0)
            instr_depth = atoi(argv[++i]);
        else if (i + 1 < argc && strcmp(argv[i], "--count") == 0)
            N = atoi(argv[++i]);
    }

    int max_all = instr_depth;
    for (unsigned oi = 0; oi < NUM_OPS; oi++) {
        int mn = max_n(&OPS[oi], data_depth, instr_depth);
        if (mn < max_all) max_all = mn;
    }
    if (N <= 0 || N > max_all) N = max_all;
    if (N < 1) {
        fprintf(stderr, "ERROR: BRAM too small for any benchmark ops\n");
        return 1;
    }

    pawn_dev_t dev;
    if (pawn_open(&dev) != 0) return 1;

    pawn_reset(&dev);
    uint64_t op_a = 0x4000000000000000ULL;
    uint64_t op_b = 0x4000000000000000ULL;
    pawn_dbram_write64(&dev, 0, &op_a, 1);
    pawn_dbram_write64(&dev, 1, &op_b, 1);

    printf("Per-op throughput (64-bit, data_depth=%d, instr_depth=%d)\n",
           data_depth, instr_depth);
    printf("  Using N=%d ops per op\n", N);
    printf("\n");
    printf("  %-12s %10s %12s %12s %10s\n",
           "Op", "N", "total ns", "ns/op", "MOPS");

    uint64_t *prog = malloc((size_t)instr_depth * sizeof(uint64_t));
    if (!prog) { perror("malloc"); pawn_close(&dev); return 1; }

    bench_csv_header("per_op");

    for (unsigned oi = 0; oi < NUM_OPS; oi++) {
        const OpInfo *op = &OPS[oi];
        int this_n = N;
        int mn = max_n(op, data_depth, instr_depth);
        if (this_n > mn) this_n = mn;
        if (this_n < 1) {
            printf("  %-12s %s\n", op->name, "SKIP");
            continue;
        }

        size_t prog_len = build_prog(prog, op, this_n);
        pawn_load_program(&dev, prog, prog_len);

        long long ns_warm = pawn_run_blocking(&dev, 10000);
        if (ns_warm < 0) {
            printf("  %-12s %s\n", op->name, "TIMEOUT (warmup)");
            continue;
        }

        long long ns = pawn_run_blocking(&dev, 10000);
        if (ns < 0) {
            printf("  %-12s %s\n", op->name, "TIMEOUT");
            continue;
        }

        double ns_per_op = (double)ns / this_n;
        double mops = bench_mops(ns, this_n);
        printf("  %-12s %10d %12.0f %12.1f %10.3f\n",
               op->name, this_n, (double)ns, ns_per_op, mops);
        printf("#CSV,per_op,64,%s,%d,%lld,%.1f,%.3f\n",
               op->name, this_n, (long long)ns, ns_per_op, mops);
    }

    free(prog);
    pawn_close(&dev);
    return 0;
}
