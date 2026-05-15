/*
 * bench_per_op.c -- PAWN per-op throughput benchmark (32-bit)
 *
 * Measures steady-state throughput (MOPS, ns/op) for every non-HALT opcode.
 * Non-quire ops fill IBRAM with N independent copies, each writing to a unique
 * result address (shared operand addresses -> no RAW hazards).
 *
 * Quire ops are benchmarked as tight sequences:
 *   QACC_MADD: QCLR + [QMADD(a,b)]*N + QREAD (N QMADD operations)
 *   QACC_ADD:  QCLR + [QADD(a)]*N    + QREAD
 *   QACC_MSUB: QCLR + [QMSUB(a,b)]*N + QREAD
 *   QACC_NEG:  QCLR + QADD(a) + [QNEG]*N + QREAD
 *   (QACC_CLEAR / QACC_READ are implicit in the above chains)
 *
 * Usage: ./bench_per_op.elf [--count N] [--data-depth N] [--instr-depth N]
 *
 *   Default count = 1000 (or max fitting BRAM if larger).
 *   --data-depth  defaults to 32768 (match config_pkg.sv).
 *   --instr-depth defaults to 32768.
 */

#include "bench_common.h"

#define DATA_DEPTH_DEFAULT  32768
#define INSTR_DEPTH_DEFAULT 32768

typedef struct {
    const char *name;
    int         opcode;
    int         is_quire;
    int         n_src;       /* 0, 1, or 2 source DBRAM reads */
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

/* ---- program builder ---- */

static size_t build_prog(uint64_t *prog, const OpInfo *op, int N)
{
    size_t n = 0;

    if (op->is_quire) {
        /* QCLR then N quire ops then QREAD */
        prog[n++] = PAWN_INSTR(PAWN_OP_QACC_CLEAR, 0, 0, 0);

        if (op->opcode == PAWN_OP_QACC_NEG) {
            /* prime the quire with a non-zero value */
            prog[n++] = PAWN_INSTR(PAWN_OP_QACC_ADD, 0, 0, 0);
        }

        for (int i = 0; i < N; i++)
            prog[n++] = PAWN_INSTR(op->opcode, op->n_src >= 1 ? 0 : 0,
                                   op->n_src >= 2 ? 1 : 0, 0);

        prog[n++] = PAWN_INSTR(PAWN_OP_QACC_READ, 0, 0, 2);
    } else {
        int result_base = op->n_src; /* 1 for unary (operand at 0), 2 for binary (op at 0,1) */
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

/* ---- max N per op given BRAM sizes ---- */

static int max_n(const OpInfo *op, int data_depth, int instr_depth)
{
    if (op->is_quire) {
        int overhead = (op->opcode == PAWN_OP_QACC_NEG) ? 4 : 3; /* QCLR + [QADD] + ... + QREAD + HALT */
        int max_instr = instr_depth - overhead;
        return max_instr > 0 ? max_instr : 0;
    }
    /* non-quire: need result_base + N distinct result addresses */
    int result_base = op->n_src; /* 1 or 2 */
    int max_data = data_depth - result_base;
    return max_data > 0 ? max_data : 0;
}

/* ---- main ---- */

int main(int argc, char *argv[])
{
    int data_depth  = DATA_DEPTH_DEFAULT;
    int instr_depth = INSTR_DEPTH_DEFAULT;
    int N           = 0; /* 0 = auto (max that fits all ops) */

    for (int i = 1; i < argc; i++) {
        if (i + 1 < argc && strcmp(argv[i], "--data-depth") == 0)
            data_depth = atoi(argv[++i]);
        else if (i + 1 < argc && strcmp(argv[i], "--instr-depth") == 0)
            instr_depth = atoi(argv[++i]);
        else if (i + 1 < argc && strcmp(argv[i], "--count") == 0)
            N = atoi(argv[++i]);
    }

    /* find max N that fits all ops */
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

    /* load operands (reused across all op benchmarks) */
    pawn_reset(&dev);
    uint32_t op_a = 0x40000000u;
    uint32_t op_b = 0x40000000u;
    pawn_dbram_write32(&dev, 0, &op_a, 1);
    pawn_dbram_write32(&dev, 1, &op_b, 1);

    printf("Per-op throughput (32-bit, data_depth=%d, instr_depth=%d)\n",
           data_depth, instr_depth);
    printf("  Using N=%d ops per op (max that fits BRAM)\n", N);
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
            printf("  %-12s %s\n", op->name, "SKIP (does not fit)");
            continue;
        }

        size_t prog_len = build_prog(prog, op, this_n);
        pawn_load_program(&dev, prog, prog_len);

        /* warm-up run */
        long long ns_warm = pawn_run_blocking(&dev, 10000);
        if (ns_warm < 0) {
            printf("  %-12s %s\n", op->name, "TIMEOUT (warmup)");
            continue;
        }

        /* measured run */
        long long ns = pawn_run_blocking(&dev, 10000);
        if (ns < 0) {
            printf("  %-12s %s\n", op->name, "TIMEOUT");
            continue;
        }

        double ns_per_op = (double)ns / this_n;
        double mops = bench_mops(ns, this_n);
        printf("  %-12s %10d %12.0f %12.1f %10.3f\n",
               op->name, this_n, (double)ns, ns_per_op, mops);
        printf("#CSV,per_op,32,%s,%d,%lld,%.1f,%.3f\n",
               op->name, this_n, (long long)ns, ns_per_op, mops);
    }

    free(prog);
    pawn_close(&dev);
    return 0;
}
