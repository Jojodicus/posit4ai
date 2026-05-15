/*
 * bench_common.h -- shared helpers for bench_gemm.c / bench_conv.c
 *
 * Pure C, no libpawn dependency.  Input data is raw posit/float bit patterns
 * (uint32_t for DATA_WIDTH<=32, uint64_t for 64).  The host is responsible for
 * encoding floats into the target format before loading; here we use random
 * uint32_t values (all valid posit32 encodings except NaR=0x80000000).
 *
 * For float<->posit conversion at larger scale, use the libpawn benchmarks on
 * an x86 host to produce encoded input files, then feed them to these programs.
 */

#ifndef BENCH_COMMON_H
#define BENCH_COMMON_H

#define _POSIX_C_SOURCE 199309L

#include "../pawn.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ---- timing ---- */

static inline long long bench_now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

/* ---- arg parsing ---- */

static inline int bench_flag(int argc, char *argv[], const char *flag)
{
    for (int i = 1; i < argc; i++)
        if (strcmp(argv[i], flag) == 0) return 1;
    return 0;
}

static inline int bench_int(int argc, char *argv[], const char *opt, int def)
{
    for (int i = 1; i < argc - 1; i++)
        if (strcmp(argv[i], opt) == 0) return atoi(argv[i+1]);
    return def;
}

/* ---- random data ---- */

/* Returns a random posit/float word.  Masked to avoid posit NaR (0x80000000). */
static inline uint32_t bench_rand32(void) { return (uint32_t)rand() & 0x7FFFFFFF; }

/* Returns a random uint64_t posit/float word.  Masked to avoid NaR. */
static inline uint64_t bench_rand64(void)
{
    return ((uint64_t)rand() << 32 | (uint64_t)rand()) & 0x7FFFFFFFFFFFFFFFull;
}

/* ---- timing report ---- */

static inline void bench_print_timing(double prog_ms,   double load_ms,
                                double compute_ms, double unload_ms,
                                long long bytes_in, long long bytes_out,
                                int tile_runs, int use_quire,
                                int k_tiling_active)
{
    double load_bw   = load_ms   > 0.0 ? (double)bytes_in  / (load_ms   * 1e3) : 0.0;
    double unload_bw = unload_ms > 0.0 ? (double)bytes_out / (unload_ms * 1e3) : 0.0;
    double total_ms  = prog_ms + load_ms + compute_ms + unload_ms;

    printf("  Mode:          %s\n", use_quire ? "quire" : "no-quire (MUL+ADD chain)");
    if (k_tiling_active)
        printf("  NOTE: K-tiling active -- quire rounded at k-tile boundaries\n");
    printf("  Tile runs:     %d\n", tile_runs);
    printf("\n");
    printf("  Program load:  %8.3f ms\n", prog_ms);
    printf("  Data load:     %8.3f ms  (%.1f MB/s, %lld B)\n",
           load_ms,   load_bw,   bytes_in);
    printf("  Compute:       %8.3f ms\n", compute_ms);
    printf("  Data readback: %8.3f ms  (%.1f MB/s, %lld B)\n",
           unload_ms, unload_bw, bytes_out);
    printf("  Total PAWN:    %8.3f ms\n", total_ms);
}

/* ---- CSV helpers ---- */

/* Print CSV header indicating what columns follow for a given benchmark type.
 * type: "gemm", "conv", or "per_op"
 */
static void bench_csv_header(const char *type)
{
    if (strcmp(type, "gemm") == 0) {
        printf("#CSV,gemm,data_width,mode,M,N,K,total_ops,total_bytes,"
               "prog_ms,load_ms,compute_ms,readback_ms,mops,ai_ops_byte\n");
    } else if (strcmp(type, "conv") == 0) {
        printf("#CSV,conv,data_width,mode,H,W,FH,FW,total_ops,total_bytes,"
               "prog_ms,load_ms,compute_ms,readback_ms,mops,ai_ops_byte\n");
    } else if (strcmp(type, "per_op") == 0) {
        printf("#CSV,per_op,data_width,op,N,total_ns,ns_op,mops\n");
    }
}

/* Compute MOPS from elapsed nanoseconds and operation count. */
static inline double bench_mops(long long elapsed_ns, long long n_ops)
{
    return elapsed_ns > 0 ? (double)n_ops / ((double)elapsed_ns / 1e9) / 1e6 : 0.0;
}

#endif /* BENCH_COMMON_H */
