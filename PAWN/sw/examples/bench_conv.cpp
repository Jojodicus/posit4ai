/*
 * bench_conv.cpp -- 2D convolution benchmark (no padding, stride=1)
 *
 * Usage: ./bench_conv <H> <W> <FH> <FW>
 *                     [--target posit32|posit64|float32|float64]
 *                     [--no-quire]
 *                     [--data-depth N]   (default 32768)
 *                     [--instr-depth N]  (default 32768)
 *
 * Input:  H x W
 * Filter: FH x FW
 * Output: (H-FH+1) x (W-FW+1)
 *
 * Uses im2col: each output pixel maps to a flat FH*FW-length patch from the input.
 * NTILE output pixels are processed per PAWN execution, sharing one filter load.
 *
 * K-tiling note: K_acc = FH*FW is always accumulated in one pass per pixel.
 * If K_acc itself doesn't fit (very large filter), the benchmark errors.
 * Output-pixel tiling (NTILE) does not lose accuracy.
 */

#include "bench_common.hpp"
#include <random>

static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s <H> <W> <FH> <FW>\n"
        "       [--target posit32|posit64|float32|float64]\n"
        "       [--no-quire]\n"
        "       [--data-depth N]   (default 32768)\n"
        "       [--instr-depth N]  (default 32768)\n",
        prog);
    exit(1);
}

/* Build im2col patch for one output pixel (y,x).
 * Writes KA = FH*FW values into dst starting at dst_offset. */
static void im2col_pixel(const std::vector<p::Number> &inp,
                         p::Number *dst, int y, int x,
                         int W, int FH, int FW)
{
    int k = 0;
    for (int fy = 0; fy < FH; fy++)
        for (int fx = 0; fx < FW; fx++)
            dst[k++] = inp[(size_t)((y+fy)*W + (x+fx))];
}

int main(int argc, char *argv[])
{
    if (argc < 5) usage(argv[0]);
    int H  = atoi(argv[1]);
    int W  = atoi(argv[2]);
    int FH = atoi(argv[3]);
    int FW = atoi(argv[4]);
    if (H < 1 || W < 1 || FH < 1 || FW < 1 || FH > H || FW > W) usage(argv[0]);

    const char *target_name = arg_str(argc, argv, "--target", "posit32");
    bool use_quire  = !arg_flag(argc, argv, "--no-quire");
    int data_depth  = arg_int(argc, argv, "--data-depth",  32768);
    int instr_depth = arg_int(argc, argv, "--instr-depth", 32768);

    auto tgt_owner = make_target(target_name);
    p::Target &tgt = *tgt_owner;

    int OH = H - FH + 1;
    int OW = W - FW + 1;
    int KA = FH * FW;
    int N_out = OH * OW;

    int NTILE = solve_conv_ntile(FH, FW, instr_depth, data_depth, use_quire);
    int n_tiles = (N_out + NTILE - 1) / NTILE;

    printf("Conv  H=%d W=%d  filter=%dx%d  output=%dx%d  target=%s  mode=%s\n",
           H, W, FH, FW, OH, OW, target_name, use_quire ? "quire" : "no-quire");
    printf("  K_acc=%d  NTILE=%d  output_pixels=%d  tile_runs=%d\n",
           KA, NTILE, N_out, n_tiles);
    printf("  data_depth=%d  instr_depth=%d\n", data_depth, instr_depth);

    /* Generate random input and filter */
    std::mt19937 rng(42);
    std::uniform_real_distribution<float> dist_inp(-1.0f, 1.0f);
    std::uniform_real_distribution<float> dist_flt(-0.5f, 0.5f);
    std::vector<p::Number> inp((size_t)(H * W));
    std::vector<p::Number> filt((size_t)(FH * FW));
    for (auto &x : inp)  x = tgt.toNumber(dist_inp(rng));
    for (auto &x : filt) x = tgt.toNumber(dist_flt(rng));

    /* Software reference */
    printf("\n  Running libpawn reference...\n");
    std::vector<p::Number> out_ref;
    long long sw_t0 = now_ns();
    ref_conv(tgt, inp, filt, out_ref, H, W, FH, FW, use_quire);
    double sw_ms = (double)(now_ns() - sw_t0) / 1e6;

    /* PAWN accelerator */
    pawn_dev_t dev;
    if (pawn_open(&dev) != 0) return 1;
    pawn_reset(&dev);

    /* DBRAM layout for a full tile:
     *   [0 .. KA-1]                filter (written once, never changes)
     *   [KA .. KA+NTILE*KA-1]      im2col patches
     *   [KA+NTILE*KA .. +NTILE-1]  output
     *   [KA+NTILE*KA+NTILE]        TMP (no-quire only) */
    int BASE_FILT  = 0;
    int BASE_PATCH = KA;

    /* Write filter to DBRAM once */
    dbram_write(&dev, BASE_FILT, filt.data(), KA, tgt.dataWidth);

    /* Pre-build program for full NTILE (reused for interior tiles) */
    std::vector<uint64_t> prog_full_first, prog_full_nonfirst;
    build_conv_prog(prog_full_first,    NTILE, KA, true,  use_quire);
    build_conv_prog(prog_full_nonfirst, NTILE, KA, false, use_quire);

    std::vector<p::Number> out_hw((size_t)N_out, tgt.toNumber(0.0f));
    /* patch_buf: NTILE * KA words; out_buf: NTILE words */
    std::vector<p::Number> patch_buf((size_t)(NTILE * KA));
    std::vector<p::Number> out_buf((size_t)NTILE);

    double t_load = 0, t_compute = 0, t_readback = 0;
    long long bytes_load = 0, bytes_read = 0;
    int word_bytes = (tgt.dataWidth <= 32) ? 4 : 8;
    bool first_tile = true;  /* only matters for --no-quire C init; each output
                                pixel is independent, so is_first_k=true always */

    printf("  Running PAWN accelerator...\n");

    for (int tile = 0; tile < n_tiles; tile++) {
        int p0    = tile * NTILE;
        int aNTILE = N_out - p0 < NTILE ? N_out - p0 : NTILE;

        /* Build im2col for this tile */
        if (aNTILE < NTILE) {
            /* Zero-pad unused rows at the end */
            for (int i = aNTILE; i < NTILE; i++)
                for (int k = 0; k < KA; k++)
                    patch_buf[(size_t)(i*KA + k)] = p::Number{0};
        }
        for (int pi = 0; pi < aNTILE; pi++) {
            int y = (p0 + pi) / OW;
            int x = (p0 + pi) % OW;
            im2col_pixel(inp, &patch_buf[(size_t)(pi * KA)], y, x, W, FH, FW);
        }

        /* Load patches */
        long long t0 = now_ns();
        dbram_write(&dev, BASE_PATCH, patch_buf.data(), NTILE * KA, tgt.dataWidth);
        t_load += (double)(now_ns() - t0);
        bytes_load += (long long)(NTILE * KA) * word_bytes;

        /* Each output pixel's accumulation is independent (is_first_k = always true).
         * No-quire: output slots need zeroing for the first pass. */
        if (!use_quire) {
            int BASE_OUT = KA + NTILE * KA;
            t0 = now_ns();
            dbram_zero(&dev, BASE_OUT, NTILE, tgt.dataWidth);
            t_load += (double)(now_ns() - t0);
            bytes_load += (long long)NTILE * word_bytes;
        }

        /* Select (or build) program */
        std::vector<uint64_t> *prog_ptr = (aNTILE == NTILE)
            ? &prog_full_first
            : nullptr;
        std::vector<uint64_t> prog_tmp;
        if (!prog_ptr) {
            build_conv_prog(prog_tmp, aNTILE, KA, true, use_quire);
            prog_ptr = &prog_tmp;
        }

        pawn_load_program_burst(&dev, prog_ptr->data(), prog_ptr->size());

        t0 = now_ns();
        long long ns = pawn_run_blocking(&dev, 30000);
        if (ns < 0) {
            fprintf(stderr, "TIMEOUT\n");
            pawn_close(&dev);
            return 1;
        }
        t_compute += (double)ns;

        /* Read back output */
        int BASE_OUT = KA + NTILE * KA;
        t0 = now_ns();
        dbram_read(&dev, BASE_OUT, out_buf.data(), aNTILE, tgt.dataWidth);
        t_readback += (double)(now_ns() - t0);
        bytes_read += (long long)aNTILE * word_bytes;

        for (int pi = 0; pi < aNTILE; pi++)
            out_hw[(size_t)(p0 + pi)] = out_buf[(size_t)pi];

        first_tile = false;
    }

    pawn_close(&dev);

    /* Correctness check */
    CheckResult cr = check_results(tgt, out_ref, out_hw);

    printf("\n");
    print_timing(t_load / 1e6, t_compute / 1e6, t_readback / 1e6,
                 sw_ms, n_tiles, bytes_load, bytes_read,
                 false /* conv tiles don't split K */, use_quire);
    printf("\n");
    printf("  Correctness (%d output pixels checked):\n", cr.n);
    printf("    max abs err: %.4e\n", cr.max_abs_err);
    printf("    max rel err: %.4e\n", cr.max_rel_err);
    printf("    RMS err:     %.4e\n", cr.rms_err);
    if (cr.any_invalid)
        printf("    WARNING: NaR/NaN mismatch between reference and HW\n");

    double pass_thresh = (tgt.dataType == p::POSIT) ? 1e-2 : 1e-4;
    bool pass = !cr.any_invalid && cr.max_rel_err < pass_thresh;
    printf("    Result: %s\n", pass ? "PASS" : "FAIL");

    (void)first_tile;
    return pass ? 0 : 1;
}
