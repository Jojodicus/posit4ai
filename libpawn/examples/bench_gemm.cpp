/*
 * bench_gemm.cpp -- libpawn GEMM reference benchmark
 *
 * Usage: ./bench_gemm <M> <N> <K>
 *                     [--target posit32|posit64|float32|float64]
 *                     [--no-quire]
 *                     [--seed N]   (default 42, must match PAWN bench_gemm)
 *
 * Generates the same random data as the PAWN bench_gemm.c (same srand/rand
 * sequence, same mask) and runs the software GEMM.  Compare the reported
 * timing against bench_gemm.elf on the Zedboard for speedup estimation.
 *
 * The "first N result words" hex dump uses raw p::Number::bits, matching the
 * uint32_t words that bench_gemm.elf reads from DBRAM.  Differences between
 * the two reflect hardware rounding (quire mode) or posit rounding vs float.
 */

#include "bench_common.hpp"

static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s <M> <N> <K>\n"
        "       [--target posit32|posit64|float32|float64]  (default posit32)\n"
        "       [--no-quire]\n"
        "       [--seed N]  (default 42)\n",
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

    const char *target_name = bench_str(argc, argv, "--target", "posit32");
    bool use_quire = !bench_flag(argc, argv, "--no-quire");
    int  seed      = bench_int(argc, argv, "--seed", 42);

    auto tgt_owner = make_target(target_name);
    p::Target &tgt = *tgt_owner;

    printf("GEMM  M=%d N=%d K=%d  target=%s  mode=%s  seed=%d\n",
           M, N, K, target_name, use_quire ? "quire" : "no-quire", seed);

    /* Generate same data as PAWN bench_gemm.c */
    srand((unsigned)seed);
    std::vector<p::Number> A, B, C;
    gen_matrix(A, M, K);
    gen_matrix(B, K, N);

    /* Warm up */
    run_gemm(tgt, A, B, C, M > 4 ? 4 : M, N > 4 ? 4 : N, K > 4 ? 4 : K, use_quire);

    /* Measured run */
    double elapsed_ms = run_gemm(tgt, A, B, C, M, N, K, use_quire);

    printf("\n");
    printf("  libpawn (%s):\n", target_name);
    printf("    Total: %8.3f ms\n", elapsed_ms);
    long long ops = (long long)M * N * K;
    printf("    Throughput: %.2f MOPS  (%.2f MFMA/s)\n",
           (double)ops / (elapsed_ms * 1e3),
           (double)ops / (elapsed_ms * 1e3));

    /* First few results for cross-check against PAWN bench */
    int show = M * N < 8 ? M * N : 8;
    printf("\n  First %d result words (hex): ", show);
    for (int i = 0; i < show; i++)
        printf("%08llX ", (unsigned long long)(C[(size_t)i].bits & 0xFFFFFFFFULL));
    printf("\n");
    printf("  (compare with bench_gemm.elf output on Zedboard using same seed)\n");

    return 0;
}
