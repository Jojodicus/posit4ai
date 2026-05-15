/*
 * bench_conv64.c -- PAWN 2D convolution benchmark (64-bit posit)
 *
 * 64-bit variant of bench_conv.c. Uses uint64_t arrays and
 * pawn_dbram_write64/read64 for DBRAM access.
 *
 * Usage: ./bench_conv64 <H> <W> <FH> <FW>
 *                       [--no-quire] [--data-depth N] [--instr-depth N] [--seed N]
 */

#include "bench_common.h"

static int solve_ntile(int FH, int FW, int instr_depth, int data_depth, int use_quire)
{
    int KA = FH * FW;
    int NT_instr = use_quire
        ? (instr_depth - 1) / (KA + 3)
        : (instr_depth - 1) / (KA * 2);
    int extra    = use_quire ? 0 : 1;
    int NT_data  = (data_depth - KA - extra) / (KA + 1);
    int NT = NT_instr < NT_data ? NT_instr : NT_data;
    if (NT < 1) {
        fprintf(stderr, "ERROR: filter %dx%d (KA=%d) does not fit in BRAM\n",
                FH, FW, KA);
        exit(1);
    }
    return NT;
}

static size_t build_prog(uint64_t *prog, int NT, int KA, int use_quire, int NTILE)
{
    size_t n      = 0;
    int BASE_FILT  = 0;
    int BASE_PATCH = KA;
    int BASE_OUT   = KA + NTILE * KA;
    int BASE_TMP   = BASE_OUT + NTILE;

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

static void im2col_pixel(const uint64_t *inp, uint64_t *dst,
                          int y, int x, int W, int FH, int FW)
{
    int k = 0;
    for (int fy = 0; fy < FH; fy++)
        for (int fx = 0; fx < FW; fx++)
            dst[k++] = inp[(y + fy) * W + (x + fx)];
}

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

    printf("Conv-64  H=%d W=%d  filter=%dx%d  output=%dx%d  mode=%s  seed=%d\n",
           H, W, FH, FW, OH, OW, use_quire ? "quire" : "no-quire", seed);
    printf("  KA=%d  NTILE=%d  output_pixels=%d  tile_runs=%d\n",
           KA, NTILE, N_out, n_tiles);
    printf("  data_depth=%d  instr_depth=%d\n", data_depth, instr_depth);

    uint64_t *inp      = malloc((size_t)(H * W)       * sizeof(uint64_t));
    uint64_t *filt     = malloc((size_t)(KA)           * sizeof(uint64_t));
    uint64_t *out      = malloc((size_t)(N_out)        * sizeof(uint64_t));
    uint64_t *patch_buf = malloc((size_t)(NTILE * KA)  * sizeof(uint64_t));
    uint64_t *out_buf   = malloc((size_t)(NTILE)        * sizeof(uint64_t));
    uint64_t *prog      = malloc((size_t)instr_depth    * sizeof(uint64_t));

    if (!inp || !filt || !out || !patch_buf || !out_buf || !prog) {
        perror("malloc"); return 1;
    }

    srand((unsigned)seed);
    for (int i = 0; i < H * W; i++) inp[i]  = bench_rand64();
    for (int i = 0; i < KA;    i++) filt[i] = bench_rand64();

    size_t prog_full_len = build_prog(prog, NTILE, KA, use_quire, NTILE);
    uint64_t *prog_full = malloc(prog_full_len * sizeof(uint64_t));
    memcpy(prog_full, prog, prog_full_len * sizeof(uint64_t));

    int BASE_FILT  = 0;
    int BASE_PATCH = KA;
    int BASE_OUT   = KA + NTILE * KA;

    pawn_dev_t dev;
    if (pawn_open(&dev) != 0) return 1;
    pawn_reset(&dev);

    pawn_dbram_write64(&dev, (uint32_t)BASE_FILT, filt, (size_t)KA);

    double t_prog = 0.0, t_load = 0.0, t_compute = 0.0, t_readback = 0.0;
    long long bytes_in = (long long)KA * 8;
    long long bytes_out = 0;

    printf("\n  Running...\n");

    for (int tile = 0; tile < n_tiles; tile++) {
        int p0     = tile * NTILE;
        int aNT    = N_out - p0 < NTILE ? N_out - p0 : NTILE;

        if (aNT < NTILE)
            memset(patch_buf + (size_t)(aNT * KA), 0,
                   (size_t)((NTILE - aNT) * KA) * sizeof(uint64_t));
        for (int pi = 0; pi < aNT; pi++) {
            int y = (p0 + pi) / OW;
            int x = (p0 + pi) % OW;
            im2col_pixel(inp, patch_buf + (size_t)(pi * KA), y, x, W, FH, FW);
        }

        long long t0 = bench_now_ns();
        pawn_dbram_write64(&dev, (uint32_t)BASE_PATCH, patch_buf,
                           (size_t)(NTILE * KA));
        t_load  += (double)(bench_now_ns() - t0);
        bytes_in += (long long)(NTILE * KA) * 8;

        uint64_t *cur_prog;
        size_t    cur_len;
        if (aNT == NTILE) {
            cur_prog = prog_full;
            cur_len  = prog_full_len;
        } else {
            cur_len  = build_prog(prog, aNT, KA, use_quire, NTILE);
            cur_prog = prog;
        }

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

        t0 = bench_now_ns();
        pawn_dbram_read64(&dev, (uint32_t)BASE_OUT, out_buf, (size_t)aNT);
        t_readback += (double)(bench_now_ns() - t0);
        bytes_out  += (long long)aNT * 8;

        for (int pi = 0; pi < aNT; pi++)
            out[p0 + pi] = out_buf[pi];
    }

    pawn_close(&dev);

    printf("\n");
    bench_print_timing(t_prog / 1e6, t_load / 1e6, t_compute / 1e6,
                       t_readback / 1e6, bytes_in, bytes_out,
                       n_tiles, use_quire, 0);

    long long total_ops = 2LL * OH * OW * FH * FW;
    long long total_bytes = bytes_in + bytes_out;
    double ai = total_bytes > 0 ? (double)total_ops / (double)total_bytes : 0.0;
    double mops = bench_mops((long long)t_compute, total_ops);
    printf("  Operations:     %lld\n", total_ops);
    printf("  MOPS:           %.3f\n", mops);
    printf("  Arithmetic int: %.2f ops/byte\n", ai);
    printf("\n");
    bench_csv_header("conv");
    printf("#CSV,conv,64,%s,%d,%d,%d,%d,%lld,%lld,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f\n",
           use_quire ? "quire" : "no-quire", H, W, FH, FW, total_ops, total_bytes,
           t_prog / 1e6, t_load / 1e6, t_compute / 1e6, t_readback / 1e6,
           mops, ai);

    int show = N_out < 8 ? N_out : 8;
    printf("\n  First %d result words (hex): ", show);
    for (int i = 0; i < show; i++) printf("%016llX ", (unsigned long long)out[i]);
    printf("\n");

    free(inp); free(filt); free(out);
    free(patch_buf); free(out_buf);
    free(prog); free(prog_full);
    return 0;
}
