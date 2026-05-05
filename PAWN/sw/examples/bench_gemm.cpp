/*
 * bench_gemm.cpp -- GEMM benchmark: (M x K) * (K x N) -> (M x N)
 *
 * Usage: ./bench_gemm <M> <N> <K>
 *                     [--target posit32|posit64|float32|float64]
 *                     [--no-quire]
 *                     [--data-depth N]   (default 32768)
 *                     [--instr-depth N]  (default 32768)
 *
 * Measures PAWN AXI data-transfer time and compute time separately.
 * Runs the same computation via libpawn for comparison.
 *
 * Tiling strategy: auto-computes (TM, TN, TK) to fit in INSTR_DEPTH and DATA_DEPTH.
 * If K > TK (K-tiling active), quire is rounded at each tile boundary --
 * accuracy is reduced but all K contributions are included.
 */

#include "bench_common.hpp"
#include <random>

static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s <M> <N> <K>\n"
        "       [--target posit32|posit64|float32|float64]\n"
        "       [--no-quire]\n"
        "       [--data-depth N]   (default 32768)\n"
        "       [--instr-depth N]  (default 32768)\n",
        prog);
    exit(1);
}

/* Pack A tile (aTM x aTK from full M x K matrix) into flat TM x TK buffer.
 * Rows/cols outside the actual tile size are zero-padded. */
static void pack_a(const std::vector<p::Number> &A, std::vector<p::Number> &tile,
                   int m0, int k0, int aTM, int aTK, int K, int TM, int TK)
{
    tile.assign((size_t)(TM * TK), p::Number{0});
    for (int i = 0; i < aTM; i++)
        for (int k = 0; k < aTK; k++)
            tile[(size_t)(i*TK + k)] = A[(size_t)((m0+i)*K + (k0+k))];
}

/* Pack B tile (aTK x aTN from full K x N matrix) into flat TK x TN buffer. */
static void pack_b(const std::vector<p::Number> &B, std::vector<p::Number> &tile,
                   int k0, int n0, int aTK, int aTN, int N, int TK, int TN)
{
    tile.assign((size_t)(TK * TN), p::Number{0});
    for (int k = 0; k < aTK; k++)
        for (int j = 0; j < aTN; j++)
            tile[(size_t)(k*TN + j)] = B[(size_t)((k0+k)*N + (n0+j))];
}

/* Scatter C tile (TM x TN) back into full M x N result matrix. */
static void scatter_c(std::vector<p::Number> &C,
                      const std::vector<p::Number> &tile,
                      int m0, int n0, int aTM, int aTN, int N, int TN)
{
    for (int i = 0; i < aTM; i++)
        for (int j = 0; j < aTN; j++)
            C[(size_t)((m0+i)*N + (n0+j))] = tile[(size_t)(i*TN + j)];
}

int main(int argc, char *argv[])
{
    if (argc < 4) usage(argv[0]);
    int M = atoi(argv[1]);
    int N = atoi(argv[2]);
    int K = atoi(argv[3]);
    if (M < 1 || N < 1 || K < 1) usage(argv[0]);

    const char *target_name = arg_str(argc, argv, "--target", "posit32");
    bool use_quire  = !arg_flag(argc, argv, "--no-quire");
    int data_depth  = arg_int(argc, argv, "--data-depth",  32768);
    int instr_depth = arg_int(argc, argv, "--instr-depth", 32768);

    auto tgt_owner = make_target(target_name);
    p::Target &tgt = *tgt_owner;

    GemmTile tp = solve_gemm_tile(K, instr_depth, data_depth, use_quire);
    bool k_tiling = (K > tp.TK);

    printf("GEMM  M=%d N=%d K=%d  target=%s  mode=%s\n",
           M, N, K, target_name, use_quire ? "quire" : "no-quire");
    printf("  Tile: TM=%d TN=%d TK=%d  data_depth=%d  instr_depth=%d\n",
           tp.TM, tp.TN, tp.TK, data_depth, instr_depth);

    int n_m = (M + tp.TM - 1) / tp.TM;
    int n_n = (N + tp.TN - 1) / tp.TN;
    int n_k = (K + tp.TK - 1) / tp.TK;
    printf("  m-tiles=%d  n-tiles=%d  k-tiles=%d  total tile runs=%d\n",
           n_m, n_n, n_k, n_m * n_n * n_k);

    /* Generate random input data */
    std::mt19937 rng(42);
    std::uniform_real_distribution<float> dist(-1.0f, 1.0f);
    std::vector<p::Number> A((size_t)(M * K));
    std::vector<p::Number> B((size_t)(K * N));
    for (auto &x : A) x = tgt.toNumber(dist(rng));
    for (auto &x : B) x = tgt.toNumber(dist(rng));

    /* Software reference */
    printf("\n  Running libpawn reference...\n");
    std::vector<p::Number> C_ref;
    long long sw_t0 = now_ns();
    ref_gemm(tgt, A, B, C_ref, M, N, K, use_quire);
    double sw_ms = (double)(now_ns() - sw_t0) / 1e6;

    /* PAWN accelerator */
    pawn_dev_t dev;
    if (pawn_open(&dev) != 0) return 1;
    pawn_reset(&dev);

    /* Pre-build programs (addresses are fixed for a given TM/TN/TK) */
    std::vector<uint64_t> prog_first_k, prog_later_k;
    build_gemm_prog(prog_first_k, tp.TM, tp.TN, tp.TK, true,  use_quire);
    build_gemm_prog(prog_later_k, tp.TM, tp.TN, tp.TK, false, use_quire);

    int BASE_C = tp.TM * tp.TK + tp.TK * tp.TN;

    std::vector<p::Number> C_hw((size_t)(M * N), tgt.toNumber(0.0f));
    std::vector<p::Number> a_tile, b_tile, c_tile((size_t)(tp.TM * tp.TN));

    double t_load = 0, t_compute = 0, t_readback = 0;
    long long bytes_load = 0, bytes_read = 0;
    int word_bytes = (tgt.dataWidth <= 32) ? 4 : 8;

    printf("  Running PAWN accelerator...\n");

    for (int m0 = 0; m0 < M; m0 += tp.TM) {
        int aTM = M - m0 < tp.TM ? M - m0 : tp.TM;
        for (int n0 = 0; n0 < N; n0 += tp.TN) {
            int aTN = N - n0 < tp.TN ? N - n0 : tp.TN;
            bool first_k = true;

            for (int k0 = 0; k0 < K; k0 += tp.TK) {
                int aTK = K - k0 < tp.TK ? K - k0 : tp.TK;
                bool is_last_k = (k0 + aTK >= K);

                /* For boundary k-tiles, rebuild program with actual TK */
                std::vector<uint64_t> *prog_ptr =
                    (aTK == tp.TK) ? (first_k ? &prog_first_k : &prog_later_k) : nullptr;
                std::vector<uint64_t> prog_tmp;
                if (!prog_ptr) {
                    build_gemm_prog(prog_tmp, tp.TM, tp.TN, aTK, first_k, use_quire);
                    prog_ptr = &prog_tmp;
                }

                /* Pack and load A, B tiles */
                pack_a(A, a_tile, m0, k0, aTM, aTK, K, tp.TM, tp.TK);
                pack_b(B, b_tile, k0, n0, aTK, aTN, N, tp.TK, tp.TN);

                /* If first k-tile: also zero-write C region so no-quire accumulates from 0 */
                long long t0 = now_ns();
                dbram_write(&dev, 0,        a_tile.data(), tp.TM * tp.TK, tgt.dataWidth);
                dbram_write(&dev, tp.TM*tp.TK, b_tile.data(), tp.TK * tp.TN, tgt.dataWidth);
                if (first_k && !use_quire)
                    dbram_zero(&dev, BASE_C, tp.TM * tp.TN, tgt.dataWidth);
                t_load += (double)(now_ns() - t0);
                bytes_load += (long long)(tp.TM*tp.TK + tp.TK*tp.TN) * word_bytes;
                if (first_k && !use_quire)
                    bytes_load += (long long)(tp.TM * tp.TN) * word_bytes;

                pawn_load_program_burst(&dev, prog_ptr->data(), prog_ptr->size());

                t0 = now_ns();
                long long ns = pawn_run_blocking(&dev, 30000);
                if (ns < 0) {
                    fprintf(stderr, "TIMEOUT\n");
                    pawn_close(&dev);
                    return 1;
                }
                t_compute += (double)ns;

                if (is_last_k) {
                    t0 = now_ns();
                    dbram_read(&dev, BASE_C, c_tile.data(), tp.TM * tp.TN, tgt.dataWidth);
                    t_readback += (double)(now_ns() - t0);
                    bytes_read += (long long)(tp.TM * tp.TN) * word_bytes;
                    scatter_c(C_hw, c_tile, m0, n0, aTM, aTN, N, tp.TN);
                }
                first_k = false;
            }
        }
    }

    pawn_close(&dev);

    /* Correctness check */
    CheckResult cr = check_results(tgt, C_ref, C_hw);

    printf("\n");
    print_timing(t_load / 1e6, t_compute / 1e6, t_readback / 1e6,
                 sw_ms, n_m * n_n * n_k, bytes_load, bytes_read,
                 k_tiling, use_quire);
    printf("\n");
    printf("  Correctness (%d elements checked):\n", cr.n);
    printf("    max abs err: %.4e\n", cr.max_abs_err);
    printf("    max rel err: %.4e\n", cr.max_rel_err);
    printf("    RMS err:     %.4e\n", cr.rms_err);
    if (cr.any_invalid)
        printf("    WARNING: NaR/NaN mismatch between reference and HW\n");

    double pass_thresh = (tgt.dataType == p::POSIT) ? 1e-2 : 1e-4;
    bool pass = !cr.any_invalid && cr.max_rel_err < pass_thresh;
    printf("    Result: %s\n", pass ? "PASS" : "FAIL");

    return pass ? 0 : 1;
}
