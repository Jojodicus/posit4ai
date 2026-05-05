/*
 * bench_conv.cpp -- libpawn 2D convolution reference benchmark
 *
 * Usage: ./bench_conv <H> <W> <FH> <FW>
 *                     [--target posit32|posit64|float32|float64]
 *                     [--no-quire]
 *                     [--seed N]   (default 42, must match PAWN bench_conv)
 *
 * Generates the same random data as the PAWN bench_conv.c and runs the
 * software convolution via libpawn.  Compare timing against bench_conv.elf
 * on the Zedboard.
 *
 * Note on data ordering: inp is generated first (H*W words), then filt
 * (FH*FW words), matching the srand/rand sequence in bench_conv.c.
 */

#include "bench_common.hpp"

static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s <H> <W> <FH> <FW>\n"
        "       [--target posit32|posit64|float32|float64]  (default posit32)\n"
        "       [--no-quire]\n"
        "       [--seed N]  (default 42)\n",
        prog);
    exit(1);
}

int main(int argc, char *argv[])
{
    if (argc < 5) usage(argv[0]);
    int H  = atoi(argv[1]);
    int W  = atoi(argv[2]);
    int FH = atoi(argv[3]);
    int FW = atoi(argv[4]);
    if (H < 1 || W < 1 || FH < 1 || FW < 1 || FH > H || FW > W) usage(argv[0]);

    const char *target_name = bench_str(argc, argv, "--target", "posit32");
    bool use_quire = !bench_flag(argc, argv, "--no-quire");
    int  seed      = bench_int(argc, argv, "--seed", 42);

    int OH = H - FH + 1;
    int OW = W - FW + 1;

    auto tgt_owner = make_target(target_name);
    p::Target &tgt = *tgt_owner;

    printf("Conv  H=%d W=%d  filter=%dx%d  output=%dx%d  target=%s  mode=%s  seed=%d\n",
           H, W, FH, FW, OH, OW, target_name,
           use_quire ? "quire" : "no-quire", seed);

    /* Generate same data as PAWN bench_conv.c */
    srand((unsigned)seed);
    std::vector<p::Number> inp, filt, out;
    gen_matrix(inp,  H, W);
    gen_matrix(filt, FH, FW);

    /* Measured run */
    double elapsed_ms = run_conv(tgt, inp, filt, out, H, W, FH, FW, use_quire);

    printf("\n");
    printf("  libpawn (%s):\n", target_name);
    printf("    Total: %8.3f ms\n", elapsed_ms);
    long long ops = (long long)OH * OW * FH * FW;
    printf("    Throughput: %.2f MFMA/s\n", (double)ops / (elapsed_ms * 1e3));

    /* First few results for cross-check against PAWN bench */
    int show = OH * OW < 8 ? OH * OW : 8;
    printf("\n  First %d result words (hex): ", show);
    for (int i = 0; i < show; i++)
        printf("%08llX ", (unsigned long long)(out[(size_t)i].bits & 0xFFFFFFFFULL));
    printf("\n");
    printf("  (compare with bench_conv.elf output on Zedboard using same seed)\n");

    return 0;
}
