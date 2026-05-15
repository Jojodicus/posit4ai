/*
 * bench_gemm64.c -- PAWN GEMM benchmark (64-bit posit)
 *
 * 64-bit variant of bench_gemm.c. Uses uint64_t arrays and
 * pawn_dbram_write64/read64 for DBRAM access.  All tile sizes and
 * instruction encoding are identical; only the data width changes.
 *
 * Usage: ./bench_gemm64 <M> <N> <K>
 *                       [--no-quire] [--data-depth N] [--instr-depth N] [--seed N]
 *
 * For comparison against software, run bench_gemm in ../../../libpawn/examples/
 * with the same M/N/K and --seed.
 */

#include "bench_common.h"

typedef struct { int TM, TN, TK; } GemmTile;

static GemmTile solve_tile(int K, int instr_depth, int data_depth, int use_quire)
{
    int dims[] = {16, 8, 4, 0};
    for (int di = 0; dims[di]; di++) {
        int D  = dims[di];
        int sq = D * D;
        int TK_instr = use_quire
            ? (instr_depth - 1) / sq - 3
            : (instr_depth - 1) / (sq * 2);
        int extra    = use_quire ? 0 : 1;
        int TK_data  = (data_depth - sq - extra) / (2 * D);
        int TK = TK_instr < TK_data ? TK_instr : TK_data;
        if (TK > K) TK = K;
        if (TK >= 1) {
            GemmTile t = {D, D, TK};
            return t;
        }
    }
    fprintf(stderr, "ERROR: cannot tile K=%d into given BRAM depths\n", K);
    exit(1);
}

static size_t build_prog(uint64_t *prog, int TM, int TN, int TK,
                         int is_first_k, int use_quire)
{
    size_t n    = 0;
    int BASE_A   = 0;
    int BASE_B   = TM * TK;
    int BASE_C   = TM * TK + TK * TN;
    int BASE_TMP = BASE_C + TM * TN;

    for (int i = 0; i < TM; i++) {
        for (int j = 0; j < TN; j++) {
            int addr_c = BASE_C + i * TN + j;
            if (use_quire) {
                prog[n++] = PAWN_INSTR(PAWN_OP_QACC_CLEAR, 0, 0, 0);
                if (!is_first_k)
                    prog[n++] = PAWN_INSTR(PAWN_OP_QACC_ADD, addr_c, 0, 0);
                for (int k = 0; k < TK; k++)
                    prog[n++] = PAWN_INSTR(PAWN_OP_QACC_MADD,
                                           BASE_A + i*TK + k,
                                           BASE_B + k*TN + j, 0);
                prog[n++] = PAWN_INSTR(PAWN_OP_QACC_READ, 0, 0, addr_c);
            } else {
                if (is_first_k) {
                    prog[n++] = PAWN_INSTR(PAWN_OP_MUL,
                                           BASE_A + i*TK, BASE_B + j, addr_c);
                    for (int k = 1; k < TK; k++) {
                        prog[n++] = PAWN_INSTR(PAWN_OP_MUL,
                                               BASE_A + i*TK + k,
                                               BASE_B + k*TN + j, BASE_TMP);
                        prog[n++] = PAWN_INSTR(PAWN_OP_ADD,
                                               addr_c, BASE_TMP, addr_c);
                    }
                } else {
                    for (int k = 0; k < TK; k++) {
                        prog[n++] = PAWN_INSTR(PAWN_OP_MUL,
                                               BASE_A + i*TK + k,
                                               BASE_B + k*TN + j, BASE_TMP);
                        prog[n++] = PAWN_INSTR(PAWN_OP_ADD,
                                               addr_c, BASE_TMP, addr_c);
                    }
                }
            }
        }
    }
    prog[n++] = PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0);
    return n;
}

static void pack_a(const uint64_t *A, uint64_t *tile,
                   int m0, int k0, int aTM, int aTK, int K, int TM, int TK)
{
    memset(tile, 0, (size_t)(TM * TK) * sizeof(uint64_t));
    for (int i = 0; i < aTM; i++)
        for (int k = 0; k < aTK; k++)
            tile[i*TK + k] = A[(m0+i)*K + (k0+k)];
}

static void pack_b(const uint64_t *B, uint64_t *tile,
                   int k0, int n0, int aTK, int aTN, int N, int TK, int TN)
{
    memset(tile, 0, (size_t)(TK * TN) * sizeof(uint64_t));
    for (int k = 0; k < aTK; k++)
        for (int j = 0; j < aTN; j++)
            tile[k*TN + j] = B[(k0+k)*N + (n0+j)];
}

static void scatter_c(uint64_t *C, const uint64_t *tile,
                      int m0, int n0, int aTM, int aTN, int N, int TN)
{
    for (int i = 0; i < aTM; i++)
        for (int j = 0; j < aTN; j++)
            C[(m0+i)*N + (n0+j)] = tile[i*TN + j];
}

static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s <M> <N> <K> [--no-quire] [--data-depth N] [--instr-depth N] [--seed N]\n",
        prog);
    exit(1);
}

int main(int argc, char *argv[])
{
    if (argc < 4) usage(argv[0]);
    int M = atoi(argv[1]);
    int N = atoi(argv[2]);
    int K = atoi(argv[3]);
    if (M < 1 || N < 1 || K < 1) usage(argv[0]);

    int use_quire   = !bench_flag(argc, argv, "--no-quire");
    int data_depth  = bench_int(argc, argv, "--data-depth",  32768);
    int instr_depth = bench_int(argc, argv, "--instr-depth", 32768);
    int seed        = bench_int(argc, argv, "--seed",        42);

    GemmTile tp = solve_tile(K, instr_depth, data_depth, use_quire);
    int k_tiling = (K > tp.TK);

    int n_m = (M + tp.TM - 1) / tp.TM;
    int n_n = (N + tp.TN - 1) / tp.TN;
    int n_k = (K + tp.TK - 1) / tp.TK;

    printf("GEMM-64  M=%d N=%d K=%d  mode=%s  seed=%d\n",
           M, N, K, use_quire ? "quire" : "no-quire", seed);
    printf("  Tile: TM=%d TN=%d TK=%d  data_depth=%d  instr_depth=%d\n",
           tp.TM, tp.TN, tp.TK, data_depth, instr_depth);
    printf("  Tiles: %d x %d x %d = %d runs\n", n_m, n_n, n_k, n_m*n_n*n_k);

    uint64_t *A      = malloc((size_t)(M * K) * sizeof(uint64_t));
    uint64_t *B      = malloc((size_t)(K * N) * sizeof(uint64_t));
    uint64_t *C      = calloc((size_t)(M * N),  sizeof(uint64_t));
    uint64_t *a_tile = malloc((size_t)(tp.TM * tp.TK) * sizeof(uint64_t));
    uint64_t *b_tile = malloc((size_t)(tp.TK * tp.TN) * sizeof(uint64_t));
    uint64_t *c_tile = malloc((size_t)(tp.TM * tp.TN) * sizeof(uint64_t));
    uint64_t *prog   = malloc((size_t)instr_depth       * sizeof(uint64_t));

    if (!A || !B || !C || !a_tile || !b_tile || !c_tile || !prog) {
        perror("malloc"); return 1;
    }

    srand((unsigned)seed);
    for (int i = 0; i < M * K; i++) A[i] = bench_rand64();
    for (int i = 0; i < K * N; i++) B[i] = bench_rand64();

    size_t prog_first_len = build_prog(prog, tp.TM, tp.TN, tp.TK, 1, use_quire);
    uint64_t *prog_first = malloc(prog_first_len * sizeof(uint64_t));
    memcpy(prog_first, prog, prog_first_len * sizeof(uint64_t));

    size_t prog_later_len = 0;
    uint64_t *prog_later  = NULL;
    if (k_tiling) {
        prog_later_len = build_prog(prog, tp.TM, tp.TN, tp.TK, 0, use_quire);
        prog_later = malloc(prog_later_len * sizeof(uint64_t));
        memcpy(prog_later, prog, prog_later_len * sizeof(uint64_t));
    }

    int BASE_C = tp.TM * tp.TK + tp.TK * tp.TN;

    pawn_dev_t dev;
    if (pawn_open(&dev) != 0) return 1;
    pawn_reset(&dev);

    double t_prog = 0.0, t_load = 0.0, t_compute = 0.0, t_readback = 0.0;
    long long bytes_in = 0, bytes_out = 0;

    printf("\n  Running...\n");

    for (int m0 = 0; m0 < M; m0 += tp.TM) {
        int aTM = M - m0 < tp.TM ? M - m0 : tp.TM;
        for (int n0 = 0; n0 < N; n0 += tp.TN) {
            int aTN = N - n0 < tp.TN ? N - n0 : tp.TN;
            int first_k = 1;

            for (int k0 = 0; k0 < K; k0 += tp.TK) {
                int aTK     = K - k0 < tp.TK ? K - k0 : tp.TK;
                int last_k  = (k0 + aTK >= K);

                uint64_t *cur_prog;
                size_t    cur_len;
                if (aTK == tp.TK) {
                    cur_prog = first_k ? prog_first : prog_later;
                    cur_len  = first_k ? prog_first_len : prog_later_len;
                } else {
                    cur_len  = build_prog(prog, tp.TM, tp.TN, aTK, first_k, use_quire);
                    cur_prog = prog;
                }

                pack_a(A, a_tile, m0, k0, aTM, aTK, K, tp.TM, tp.TK);
                pack_b(B, b_tile, k0, n0, aTK, aTN, N, tp.TK, tp.TN);

                long long t0 = bench_now_ns();
                pawn_dbram_write64(&dev, 0,          a_tile, (size_t)(tp.TM * tp.TK));
                pawn_dbram_write64(&dev, (uint32_t)(tp.TM * tp.TK), b_tile,
                                   (size_t)(tp.TK * tp.TN));
                if (!use_quire && first_k) {
                    memset(c_tile, 0, (size_t)(tp.TM * tp.TN) * sizeof(uint64_t));
                    pawn_dbram_write64(&dev, (uint32_t)BASE_C, c_tile,
                                       (size_t)(tp.TM * tp.TN));
                }
                t_load += (double)(bench_now_ns() - t0);
                bytes_in += (long long)(tp.TM * tp.TK + tp.TK * tp.TN) * 8;
                if (!use_quire && first_k)
                    bytes_in += (long long)(tp.TM * tp.TN) * 8;

                t0 = bench_now_ns();
                pawn_load_program(&dev, cur_prog, cur_len);
                t_prog += (double)(bench_now_ns() - t0);

                t0 = bench_now_ns();
                long long ns = pawn_run_blocking(&dev, 30000);
                if (ns < 0) {
                    fprintf(stderr, "TIMEOUT\n");
                    pawn_close(&dev);
                    return 1;
                }
                t_compute += (double)ns;

                if (last_k) {
                    t0 = bench_now_ns();
                    pawn_dbram_read64(&dev, (uint32_t)BASE_C, c_tile,
                                      (size_t)(tp.TM * tp.TN));
                    t_readback += (double)(bench_now_ns() - t0);
                    bytes_out  += (long long)(tp.TM * tp.TN) * 8;
                    scatter_c(C, c_tile, m0, n0, aTM, aTN, N, tp.TN);
                }
                first_k = 0;
            }
        }
    }

    pawn_close(&dev);

    printf("\n");
    bench_print_timing(t_prog / 1e6, t_load / 1e6, t_compute / 1e6,
                       t_readback / 1e6, bytes_in, bytes_out,
                       n_m * n_n * n_k, use_quire, k_tiling);

    long long total_ops = 2LL * M * N * K;
    long long total_bytes = bytes_in + bytes_out;
    double ai = total_bytes > 0 ? (double)total_ops / (double)total_bytes : 0.0;
    double mops = bench_mops((long long)t_compute, total_ops);
    printf("  Operations:     %lld\n", total_ops);
    printf("  MOPS:           %.3f\n", mops);
    printf("  Arithmetic int: %.2f ops/byte\n", ai);
    printf("\n");
    bench_csv_header("gemm");
    printf("#CSV,gemm,64,%s,%d,%d,%d,%lld,%lld,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f\n",
           use_quire ? "quire" : "no-quire", M, N, K, total_ops, total_bytes,
           t_prog / 1e6, t_load / 1e6, t_compute / 1e6, t_readback / 1e6,
           mops, ai);

    int show = M * N < 8 ? M * N : 8;
    printf("\n  First %d result words (hex): ", show);
    for (int i = 0; i < show; i++) printf("%016llX ", (unsigned long long)C[i]);
    printf("\n");

    free(A); free(B); free(C);
    free(a_tile); free(b_tile); free(c_tile);
    free(prog); free(prog_first); free(prog_later);
    return 0;
}
