/*
 * bench_common.hpp -- shared utilities for libpawn GEMM/conv benchmarks
 *
 * Runs on x86 (not on the Zedboard).  Provides the software reference
 * timing counterpart to sw/examples/bench_gemm.c and bench_conv.c.
 *
 * Data representation: random uint32_t values generated with the same
 * srand(seed) + rand() sequence as the PAWN C benchmarks, interpreted as
 * raw posit/float bit patterns via p::Number{bits}.  This makes the
 * "first N result words" output comparable between the two sides.
 *
 * Note on float<->posit conversion: currently the host must pre-encode data
 * into posit format before loading it onto the accelerator.  A future PAWN
 * opcode may handle on-chip conversion.
 */

#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <chrono>
#include <memory>
#include <string>
#include <vector>
#include "libpawn.hpp"

/* ---- timing ---- */

static inline double now_ms()
{
    using clock = std::chrono::high_resolution_clock;
    using ms    = std::chrono::duration<double, std::milli>;
    return std::chrono::duration_cast<ms>(clock::now().time_since_epoch()).count();
}

/* ---- target factory ---- */

static inline std::unique_ptr<p::Target> make_target(const char *name)
{
    if (strcmp(name, "posit32") == 0) return std::make_unique<p::Posit32Target>();
    if (strcmp(name, "posit64") == 0) return std::make_unique<p::Posit64Target>();
    if (strcmp(name, "float32") == 0) return std::make_unique<p::Float32Target>();
    if (strcmp(name, "float64") == 0) return std::make_unique<p::Float64Target>();
    fprintf(stderr, "unknown target '%s' (posit32|posit64|float32|float64)\n", name);
    exit(1);
}

/* ---- data generation (same sequence as PAWN C benchmarks) ---- */

/* Mirrors bench_rand32() in bench_common.h */
static inline uint32_t bench_rand32() { return (uint32_t)rand() & 0x7FFFFFFF; }

static inline p::Number rand_number(unsigned int /*ignored -- rand state global*/)
{
    return p::Number{(uint64_t)bench_rand32()};
}

/* Generate M*K random Numbers seeded with `seed`, store in A (row-major M x K). */
static void gen_matrix(std::vector<p::Number> &A, int rows, int cols)
{
    A.resize((size_t)(rows * cols));
    for (auto &x : A) x = p::Number{(uint64_t)bench_rand32()};
}

/* ---- arg parsing ---- */

static inline bool bench_flag(int argc, char *argv[], const char *flag)
{
    for (int i = 1; i < argc; i++)
        if (strcmp(argv[i], flag) == 0) return true;
    return false;
}

static inline const char *bench_str(int argc, char *argv[],
                                    const char *opt, const char *def)
{
    for (int i = 1; i < argc - 1; i++)
        if (strcmp(argv[i], opt) == 0) return argv[i+1];
    return def;
}

static inline int bench_int(int argc, char *argv[], const char *opt, int def)
{
    const char *s = bench_str(argc, argv, opt, nullptr);
    return s ? atoi(s) : def;
}

/* ---- GEMM reference: (M x K) * (K x N) -> (M x N) ---- */

static double run_gemm(p::Target &tgt,
                       const std::vector<p::Number> &A,
                       const std::vector<p::Number> &B,
                       std::vector<p::Number> &C,
                       int M, int N, int K, bool use_quire)
{
    C.assign((size_t)(M * N), tgt.toNumber(0.0f));
    double t0 = now_ms();
    for (int i = 0; i < M; i++) {
        for (int j = 0; j < N; j++) {
            if (use_quire) {
                tgt.qaClear();
                for (int k = 0; k < K; k++)
                    tgt.qaFma(A[(size_t)(i*K+k)], B[(size_t)(k*N+j)]);
                C[(size_t)(i*N+j)] = tgt.qaRead();
            } else {
                p::Number acc = tgt.toNumber(0.0f);
                for (int k = 0; k < K; k++)
                    acc = tgt.add(acc, tgt.mul(A[(size_t)(i*K+k)],
                                               B[(size_t)(k*N+j)]));
                C[(size_t)(i*N+j)] = acc;
            }
        }
    }
    return now_ms() - t0;
}

/* ---- Conv reference: (H x W) * (FH x FW) -> (OH x OW), no padding ---- */

static double run_conv(p::Target &tgt,
                       const std::vector<p::Number> &inp,
                       const std::vector<p::Number> &filt,
                       std::vector<p::Number> &out,
                       int H, int W, int FH, int FW, bool use_quire)
{
    int OH = H - FH + 1, OW = W - FW + 1;
    out.assign((size_t)(OH * OW), tgt.toNumber(0.0f));
    double t0 = now_ms();
    for (int y = 0; y < OH; y++) {
        for (int x = 0; x < OW; x++) {
            if (use_quire) {
                tgt.qaClear();
                for (int fy = 0; fy < FH; fy++)
                    for (int fx = 0; fx < FW; fx++)
                        tgt.qaFma(inp[(size_t)((y+fy)*W+(x+fx))],
                                  filt[(size_t)(fy*FW+fx)]);
                out[(size_t)(y*OW+x)] = tgt.qaRead();
            } else {
                p::Number acc = tgt.toNumber(0.0f);
                for (int fy = 0; fy < FH; fy++)
                    for (int fx = 0; fx < FW; fx++)
                        acc = tgt.add(acc,
                                  tgt.mul(inp[(size_t)((y+fy)*W+(x+fx))],
                                          filt[(size_t)(fy*FW+fx)]));
                out[(size_t)(y*OW+x)] = acc;
            }
        }
    }
    return now_ms() - t0;
}
