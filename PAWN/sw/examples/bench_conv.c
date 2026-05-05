/*
 * bench_conv.c -- PAWN 2D convolution benchmark (no padding, stride=1)
 *
 * Usage: ./bench_conv <H> <W> <FH> <FW>
 *                     [--no-quire]
 *                     [--data-depth N]   (default 32768)
 *                     [--instr-depth N]  (default 32768)
 *                     [--seed N]         (default 42)
 *
 * Input:  H x W image
 * Filter: FH x FW kernel
 * Output: (H-FH+1) x (W-FW+1)
 *
 * Uses im2col internally: for each output pixel (y,x), extract the flat
 * FH*FW-length input patch.  NTILE pixels are processed per PAWN execution.
 *
 * DBRAM layout (constant for a given NTILE and KA=FH*FW):
 *   [0 .. KA-1]                  filter (FH*FW words; loaded once)
 *   [KA .. KA+NTILE*KA-1]        im2col patches (NTILE rows x KA cols)
 *   [KA+NTILE*KA .. +NTILE-1]    output (NTILE words)
 *   [KA+NTILE*KA+NTILE]          TMP (no-quire only)
 *
 * Each output pixel's accumulation is independent (no K-tiling across pixels).
 * K-tiling within a single pixel (KA > capacity) is an error for typical filters.
 */

#include "bench_common.h"

/* ---- tile solver ---- */

/* Returns NTILE: max output pixels per PAWN execution. */
static int solve_ntile(int FH, int FW, int instr_depth, int data_depth, int use_quire)
{
    int KA = FH * FW;
    /* Per pixel: worst-case KA+3 (quire with reload) or 2*KA (no-quire) */
    int NT_instr = use_quire
        ? (instr_depth - 1) / (KA + 3)
        : (instr_depth - 1) / (KA * 2);
    int extra    = use_quire ? 0 : 1;   /* TMP slot */
    int NT_data  = (data_depth - KA - extra) / (KA + 1);
    int NT = NT_instr < NT_data ? NT_instr : NT_data;
    if (NT < 1) {
        fprintf(stderr, "ERROR: filter %dx%d (KA=%d) does not fit in BRAM\n",
                FH, FW, KA);
        exit(1);
    }
    return NT;
}

/* ---- program builder ---- */

/* Builds program for aNT output pixels, each with KA accumulations.
 * is_first: true for every tile (each pixel is independent, so always first).
 */
static size_t build_prog(uint64_t *prog, int NT, int KA, int use_quire)
{
    size_t n      = 0;
    int BASE_FILT  = 0;
    int BASE_PATCH = KA;
    int BASE_OUT   = KA + NT * KA;
    int BASE_TMP   = BASE_OUT + NT;

    for (int p = 0; p < NT; p++) {
        int addr_out = BASE_OUT + p;
        if (use_quire) {
            prog[n++] = PAWN_INSTR(PAWN_OP_QACC_CLEAR, 0, 0, 0);
            for (int k = 0; k < KA; k++)
                prog[n++] = PAWN_INSTR(PAWN_OP_QACC_MADD,
                                       BASE_PATCH + p*KA + k,
                                       BASE_FILT  + k, 0);
            prog[n++] = PAWN_INSTR(PAWN_OP_QACC_READ, 0, 0, addr_out);
        } else {
            prog[n++] = PAWN_INSTR(PAWN_OP_MUL,
                                   BASE_PATCH + p*KA, BASE_FILT, addr_out);
            for (int k = 1; k < KA; k++) {
                prog[n++] = PAWN_INSTR(PAWN_OP_MUL,
                                       BASE_PATCH + p*KA + k,
                                       BASE_FILT  + k, BASE_TMP);
                prog[n++] = PAWN_INSTR(PAWN_OP_ADD, addr_out, BASE_TMP, addr_out);
            }
        }
    }
    prog[n++] = PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0);
    return n;
}

/* ---- im2col ---- */

/* Extract one output pixel's receptive field into dst[0..KA-1]. */
static void im2col_pixel(const uint32_t *inp, uint32_t *dst,
                          int y, int x, int W, int FH, int FW)
{
    int k = 0;
    for (int fy = 0; fy < FH; fy++)
        for (int fx = 0; fx < FW; fx++)
            dst[k++] = inp[(y + fy) * W + (x + fx)];
}

/* ---- main ---- */

static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s <H> <W> <FH> <FW> [--no-quire] [--data-depth N] "
        "[--instr-depth N] [--seed N]\n",
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

    int use_quire   = !bench_flag(argc, argv, "--no-quire");
    int data_depth  = bench_int(argc, argv, "--data-depth",  32768);
    int instr_depth = bench_int(argc, argv, "--instr-depth", 32768);
    int seed        = bench_int(argc, argv, "--seed",        42);

    int OH    = H - FH + 1;
    int OW    = W - FW + 1;
    int KA    = FH * FW;
    int N_out = OH * OW;

    int NTILE   = solve_ntile(FH, FW, instr_depth, data_depth, use_quire);
    int n_tiles = (N_out + NTILE - 1) / NTILE;

    printf("Conv  H=%d W=%d  filter=%dx%d  output=%dx%d  mode=%s  seed=%d\n",
           H, W, FH, FW, OH, OW, use_quire ? "quire" : "no-quire", seed);
    printf("  KA=%d  NTILE=%d  output_pixels=%d  tile_runs=%d\n",
           KA, NTILE, N_out, n_tiles);
    printf("  data_depth=%d  instr_depth=%d\n", data_depth, instr_depth);

    /* Allocate buffers */
    uint32_t *inp      = malloc((size_t)(H * W)       * sizeof(uint32_t));
    uint32_t *filt     = malloc((size_t)(KA)           * sizeof(uint32_t));
    uint32_t *out      = malloc((size_t)(N_out)        * sizeof(uint32_t));
    uint32_t *patch_buf = malloc((size_t)(NTILE * KA)  * sizeof(uint32_t));
    uint32_t *out_buf   = malloc((size_t)(NTILE)        * sizeof(uint32_t));
    uint64_t *prog      = malloc((size_t)instr_depth    * sizeof(uint64_t));

    if (!inp || !filt || !out || !patch_buf || !out_buf || !prog) {
        perror("malloc"); return 1;
    }

    /* Generate deterministic random data */
    srand((unsigned)seed);
    for (int i = 0; i < H * W; i++) inp[i]  = bench_rand32();
    for (int i = 0; i < KA;    i++) filt[i] = bench_rand32();

    /* Pre-build full-tile program (reused for interior tiles) */
    size_t prog_full_len = build_prog(prog, NTILE, KA, use_quire);
    uint64_t *prog_full = malloc(prog_full_len * sizeof(uint64_t));
    memcpy(prog_full, prog, prog_full_len * sizeof(uint64_t));

    int BASE_FILT  = 0;
    int BASE_PATCH = KA;
    int BASE_OUT   = KA + NTILE * KA;

    /* Open accelerator */
    pawn_dev_t dev;
    if (pawn_open(&dev) != 0) return 1;
    pawn_reset(&dev);

    /* Write filter once -- does not change between tiles */
    pawn_dbram_write32(&dev, (uint32_t)BASE_FILT, filt, (size_t)KA);

    double t_load = 0.0, t_compute = 0.0, t_readback = 0.0;
    long long bytes_in = (long long)KA * 4;   /* filter loaded upfront */
    long long bytes_out = 0;

    printf("\n  Running...\n");

    for (int tile = 0; tile < n_tiles; tile++) {
        int p0     = tile * NTILE;
        int aNT    = N_out - p0 < NTILE ? N_out - p0 : NTILE;

        /* Build im2col patches for this tile */
        if (aNT < NTILE)
            memset(patch_buf + (size_t)(aNT * KA), 0,
                   (size_t)((NTILE - aNT) * KA) * sizeof(uint32_t));
        for (int pi = 0; pi < aNT; pi++) {
            int y = (p0 + pi) / OW;
            int x = (p0 + pi) % OW;
            im2col_pixel(inp, patch_buf + (size_t)(pi * KA), y, x, W, FH, FW);
        }

        long long t0 = bench_now_ns();
        pawn_dbram_write32(&dev, (uint32_t)BASE_PATCH, patch_buf,
                           (size_t)(NTILE * KA));
        t_load  += (double)(bench_now_ns() - t0);
        bytes_in += (long long)(NTILE * KA) * 4;

        /* Select or build program */
        uint64_t *cur_prog;
        size_t    cur_len;
        if (aNT == NTILE) {
            cur_prog = prog_full;
            cur_len  = prog_full_len;
        } else {
            cur_len  = build_prog(prog, aNT, KA, use_quire);
            cur_prog = prog;
        }

        pawn_load_program_burst(&dev, cur_prog, cur_len);

        t0 = bench_now_ns();
        long long ns = pawn_run_blocking(&dev, 30000);
        if (ns < 0) {
            fprintf(stderr, "TIMEOUT\n");
            pawn_close(&dev);
            return 1;
        }
        t_compute += (double)ns;

        t0 = bench_now_ns();
        pawn_dbram_read32(&dev, (uint32_t)BASE_OUT, out_buf, (size_t)aNT);
        t_readback += (double)(bench_now_ns() - t0);
        bytes_out  += (long long)aNT * 4;

        for (int pi = 0; pi < aNT; pi++)
            out[p0 + pi] = out_buf[pi];
    }

    pawn_close(&dev);

    printf("\n");
    bench_print_timing(t_load / 1e6, t_compute / 1e6, t_readback / 1e6,
                       bytes_in, bytes_out, n_tiles, use_quire, 0);

    /* Print a few result words for cross-check against libpawn SW bench */
    int show = N_out < 8 ? N_out : 8;
    printf("\n  First %d result words (hex): ", show);
    for (int i = 0; i < show; i++) printf("%08X ", out[i]);
    printf("\n");

    free(inp); free(filt); free(out);
    free(patch_buf); free(out_buf);
    free(prog); free(prog_full);
    return 0;
}
