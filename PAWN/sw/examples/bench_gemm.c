/*
 * bench_gemm.c -- PAWN GEMM benchmark: (M x K) * (K x N) -> (M x N)
 *
 * Usage: ./bench_gemm <M> <N> <K>
 *                     [--no-quire]
 *                     [--data-depth N]   (default 32768, match config_pkg.sv)
 *                     [--instr-depth N]  (default 32768)
 *                     [--seed N]         (default 42)
 *
 * Input data: random uint32_t words (valid posit32 / float32 raw encodings).
 * For comparison against software, run bench_gemm in ../../../libpawn/examples/
 * with the same M/N/K and --seed.
 *
 * Tiling strategy:
 *   Auto-computes (TM, TN, TK) to fit in INSTR_DEPTH and DATA_DEPTH.
 *   With quire:    per output element: QCLR [+ QACC_ADD] + TK*QMADD + QREAD = TK+2/TK+3 instrs
 *   Without quire: per output element: MUL + (TK-1)*(MUL+ADD) = 2*TK-1/2*TK instrs
 *
 *   If K > TK (K-tiling), intermediate QREAD+QACC_ADD reloads round the quire
 *   at tile boundaries (documented in output).  K <= TK keeps full quire precision.
 *
 * DBRAM layout (constant for a given TM, TN, TK; boundary tiles are zero-padded):
 *   [0 .. TM*TK-1]              A_tile  (TM rows x TK cols, row-major)
 *   [TM*TK .. TM*TK+TK*TN-1]   B_tile  (TK rows x TN cols, row-major)
 *   [TM*TK+TK*TN .. +TM*TN-1]  C_tile  result
 *   [TM*TK+TK*TN+TM*TN]        TMP     (no-quire only)
 */

#include "bench_common.h"

/* ---- tile solver ---- */

typedef struct { int TM, TN, TK; } GemmTile;

static GemmTile solve_tile(int K, int instr_depth, int data_depth, int use_quire)
{
    int dims[] = {16, 8, 4, 0};
    for (int di = 0; dims[di]; di++) {
        int D  = dims[di];
        int sq = D * D;
        /* Worst-case instructions per element: TK+3 (quire) or 2*TK (no-quire) */
        int TK_instr = use_quire
            ? (instr_depth - 1) / sq - 3
            : (instr_depth - 1) / (sq * 2);
        int extra    = use_quire ? 0 : 1;   /* TMP slot for no-quire */
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

/* ---- program builder ---- */

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
                /* k_tile 0: MUL first product directly into C, then MUL+ADD for rest */
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

/* ---- tile packing ---- */

/* Pack A_tile (aTM x aTK from row-major M x K matrix) into TM x TK buffer. */
static void pack_a(const uint32_t *A, uint32_t *tile,
                   int m0, int k0, int aTM, int aTK, int K, int TM, int TK)
{
    memset(tile, 0, (size_t)(TM * TK) * sizeof(uint32_t));
    for (int i = 0; i < aTM; i++)
        for (int k = 0; k < aTK; k++)
            tile[i*TK + k] = A[(m0+i)*K + (k0+k)];
}

/* Pack B_tile (aTK x aTN from row-major K x N matrix) into TK x TN buffer. */
static void pack_b(const uint32_t *B, uint32_t *tile,
                   int k0, int n0, int aTK, int aTN, int N, int TK, int TN)
{
    memset(tile, 0, (size_t)(TK * TN) * sizeof(uint32_t));
    for (int k = 0; k < aTK; k++)
        for (int j = 0; j < aTN; j++)
            tile[k*TN + j] = B[(k0+k)*N + (n0+j)];
}

/* Scatter C_tile result (TM x TN) back into full M x N matrix. */
static void scatter_c(uint32_t *C, const uint32_t *tile,
                      int m0, int n0, int aTM, int aTN, int N, int TN)
{
    for (int i = 0; i < aTM; i++)
        for (int j = 0; j < aTN; j++)
            C[(m0+i)*N + (n0+j)] = tile[i*TN + j];
}

/* ---- main ---- */

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

    printf("GEMM  M=%d N=%d K=%d  mode=%s  seed=%d\n",
           M, N, K, use_quire ? "quire" : "no-quire", seed);
    printf("  Tile: TM=%d TN=%d TK=%d  data_depth=%d  instr_depth=%d\n",
           tp.TM, tp.TN, tp.TK, data_depth, instr_depth);
    printf("  Tiles: %d x %d x %d = %d runs\n", n_m, n_n, n_k, n_m*n_n*n_k);

    /* Allocate buffers */
    uint32_t *A      = malloc((size_t)(M * K) * sizeof(uint32_t));
    uint32_t *B      = malloc((size_t)(K * N) * sizeof(uint32_t));
    uint32_t *C      = calloc((size_t)(M * N),  sizeof(uint32_t));
    uint32_t *a_tile = malloc((size_t)(tp.TM * tp.TK) * sizeof(uint32_t));
    uint32_t *b_tile = malloc((size_t)(tp.TK * tp.TN) * sizeof(uint32_t));
    uint32_t *c_tile = malloc((size_t)(tp.TM * tp.TN) * sizeof(uint32_t));
    uint64_t *prog   = malloc((size_t)instr_depth       * sizeof(uint64_t));

    if (!A || !B || !C || !a_tile || !b_tile || !c_tile || !prog) {
        perror("malloc"); return 1;
    }

    /* Generate deterministic random data */
    srand((unsigned)seed);
    for (int i = 0; i < M * K; i++) A[i] = bench_rand32();
    for (int i = 0; i < K * N; i++) B[i] = bench_rand32();

    /* Pre-build programs (fixed addresses for full tile; reused across m/n tiles) */
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

    /* Open accelerator */
    pawn_dev_t dev;
    if (pawn_open(&dev) != 0) return 1;
    pawn_reset(&dev);

    double t_load = 0.0, t_compute = 0.0, t_readback = 0.0;
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

                /* Build smaller program for boundary k-tiles with aTK < TK */
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
                pawn_dbram_write32(&dev, 0,          a_tile, (size_t)(tp.TM * tp.TK));
                pawn_dbram_write32(&dev, (uint32_t)(tp.TM * tp.TK), b_tile,
                                   (size_t)(tp.TK * tp.TN));
                /* For no-quire + first k-tile: zero C region so accumulation starts from 0 */
                if (!use_quire && first_k) {
                    memset(c_tile, 0, (size_t)(tp.TM * tp.TN) * sizeof(uint32_t));
                    pawn_dbram_write32(&dev, (uint32_t)BASE_C, c_tile,
                                       (size_t)(tp.TM * tp.TN));
                }
                t_load += (double)(bench_now_ns() - t0);
                bytes_in += (long long)(tp.TM * tp.TK + tp.TK * tp.TN) * 4;
                if (!use_quire && first_k)
                    bytes_in += (long long)(tp.TM * tp.TN) * 4;

                pawn_load_program(&dev, cur_prog, cur_len);

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
                    pawn_dbram_read32(&dev, (uint32_t)BASE_C, c_tile,
                                      (size_t)(tp.TM * tp.TN));
                    t_readback += (double)(bench_now_ns() - t0);
                    bytes_out  += (long long)(tp.TM * tp.TN) * 4;
                    scatter_c(C, c_tile, m0, n0, aTM, aTN, N, tp.TN);
                }
                first_k = 0;
            }
        }
    }

    pawn_close(&dev);

    printf("\n");
    bench_print_timing(t_load / 1e6, t_compute / 1e6, t_readback / 1e6,
                       bytes_in, bytes_out, n_m * n_n * n_k,
                       use_quire, k_tiling);

    /* Print a few result words for cross-check against libpawn SW bench */
    int show = M * N < 8 ? M * N : 8;
    printf("\n  First %d result words (hex): ", show);
    for (int i = 0; i < show; i++) printf("%08X ", C[i]);
    printf("\n");

    free(A); free(B); free(C);
    free(a_tile); free(b_tile); free(c_tile);
    free(prog); free(prog_first); free(prog_later);
    return 0;
}
