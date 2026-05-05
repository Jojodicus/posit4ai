/*
 * bench_common.hpp -- shared utilities for GEMM and conv benchmarks
 *
 * Tile solvers, timing, libpawn reference implementations, DBRAM helpers.
 */

#pragma once
#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <vector>
#include <string>
#include <memory>
#include <time.h>
#include "libpawn.hpp"

extern "C" {
#include "../pawn.h"
}

/* ---- timing ---- */

static inline long long now_ns()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
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

/* ---- DBRAM bulk helpers ---- */
/* Numbers are stored as raw bits; for 32-bit targets: bits[31:0]; 64-bit: bits[63:0] */

static void dbram_write(pawn_dev_t *dev, int base,
                        const p::Number *nums, int n, uint32_t data_width)
{
    if (data_width <= 32) {
        std::vector<uint32_t> buf((size_t)n);
        for (int i = 0; i < n; i++) buf[(size_t)i] = (uint32_t)nums[i].bits;
        pawn_dbram_write32(dev, (uint32_t)base, buf.data(), (size_t)n);
    } else {
        std::vector<uint64_t> buf((size_t)n);
        for (int i = 0; i < n; i++) buf[(size_t)i] = nums[i].bits;
        pawn_dbram_write64(dev, (uint32_t)base, buf.data(), (size_t)n);
    }
}

static void dbram_read(pawn_dev_t *dev, int base,
                       p::Number *nums, int n, uint32_t data_width)
{
    if (data_width <= 32) {
        std::vector<uint32_t> buf((size_t)n);
        pawn_dbram_read32(dev, (uint32_t)base, buf.data(), (size_t)n);
        for (int i = 0; i < n; i++) nums[i] = p::Number{(uint64_t)buf[(size_t)i]};
    } else {
        std::vector<uint64_t> buf((size_t)n);
        pawn_dbram_read64(dev, (uint32_t)base, buf.data(), (size_t)n);
        for (int i = 0; i < n; i++) nums[i] = p::Number{buf[(size_t)i]};
    }
}

/* Write n zero words starting at base. */
static void dbram_zero(pawn_dev_t *dev, int base, int n, uint32_t data_width)
{
    std::vector<p::Number> z((size_t)n, p::Number{0});
    dbram_write(dev, base, z.data(), n, data_width);
}

/* ---- tile params ---- */

struct GemmTile {
    int TM, TN, TK;
};

/* Compute max TK for given TM,TN.
 * use_quire=true:  worst-case instr/elem = TK+3 (QCLR+QACC_ADD+TK*QMADD+QREAD)
 * use_quire=false: worst-case instr/elem = 2*TK (MUL+ADD each) */
static int solve_tk(int TM, int TN, int TK_want,
                    int instr_depth, int data_depth, bool use_quire)
{
    int base = TM * TN;
    int TK_instr = use_quire
        ? (instr_depth - 1) / base - 3
        : (instr_depth - 1) / (base * 2);
    int extra   = use_quire ? 0 : 1;   /* tmp slot for no-quire */
    int TK_data = (data_depth - base - extra) / (TM + TN);
    int TK      = TK_instr < TK_data ? TK_instr : TK_data;
    return TK < TK_want ? TK : TK_want;
}

static GemmTile solve_gemm_tile(int K, int instr_depth, int data_depth, bool use_quire)
{
    for (int dim : {16, 8, 4}) {
        int TK = solve_tk(dim, dim, K, instr_depth, data_depth, use_quire);
        if (TK >= 1)
            return {dim, dim, TK};
    }
    fprintf(stderr, "ERROR: cannot tile K=%d into BRAM\n", K);
    exit(1);
}

/* Max output pixels per tile for conv. K_acc = FH*FW is never split here;
 * if K_acc itself is too large for one element the solver errors. */
static int solve_conv_ntile(int FH, int FW, int instr_depth, int data_depth, bool use_quire)
{
    int KA = FH * FW;
    int NTILE_instr = use_quire
        ? (instr_depth - 1) / (KA + 3)   /* QCLR+QACC_ADD+KA*QMADD+QREAD */
        : (instr_depth - 1) / (KA * 2);
    int extra      = use_quire ? 0 : 1;
    int NTILE_data = (data_depth - KA - extra) / (KA + 1);
    int NTILE      = NTILE_instr < NTILE_data ? NTILE_instr : NTILE_data;
    if (NTILE < 1) {
        fprintf(stderr, "ERROR: filter %dx%d (K_acc=%d) does not fit in BRAM\n", FH, FW, KA);
        exit(1);
    }
    return NTILE;
}

/* ---- libpawn reference GEMM (M x K) * (K x N) -> M x N ---- */
static void ref_gemm(p::Target &tgt,
                     const std::vector<p::Number> &A,
                     const std::vector<p::Number> &B,
                     std::vector<p::Number> &C,
                     int M, int N, int K, bool use_quire)
{
    C.assign((size_t)(M * N), tgt.toNumber(0.0f));
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
                    acc = tgt.add(acc, tgt.mul(A[(size_t)(i*K+k)], B[(size_t)(k*N+j)]));
                C[(size_t)(i*N+j)] = acc;
            }
        }
    }
}

/* ---- libpawn reference conv (no padding, stride=1) ---- */
static void ref_conv(p::Target &tgt,
                     const std::vector<p::Number> &inp,
                     const std::vector<p::Number> &filt,
                     std::vector<p::Number> &out,
                     int H, int W, int FH, int FW, bool use_quire)
{
    int OH = H - FH + 1, OW = W - FW + 1;
    out.assign((size_t)(OH * OW), tgt.toNumber(0.0f));
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
}

/* ---- correctness check ---- */
struct CheckResult {
    double max_abs_err;
    double max_rel_err;
    double rms_err;
    bool   any_invalid;
    int    n;
};

static CheckResult check_results(p::Target &tgt,
                                 const std::vector<p::Number> &ref,
                                 const std::vector<p::Number> &got)
{
    CheckResult r = {};
    r.n = (int)ref.size();
    double sq_sum = 0.0;
    for (int i = 0; i < r.n; i++) {
        double rv = tgt.toDouble(ref[(size_t)i]);
        double gv = tgt.toDouble(got[(size_t)i]);
        if (!std::isfinite(rv) || !std::isfinite(gv)) {
            if (rv != rv && gv != gv) continue;   /* both NaN/NaR -- treat as equal */
            r.any_invalid = true;
            continue;
        }
        double ae = std::fabs(rv - gv);
        double re = std::fabs(rv) > 1e-30 ? ae / std::fabs(rv) : ae;
        if (ae > r.max_abs_err) r.max_abs_err = ae;
        if (re > r.max_rel_err) r.max_rel_err = re;
        sq_sum += ae * ae;
    }
    if (r.n > 0) r.rms_err = std::sqrt(sq_sum / r.n);
    return r;
}

/* ---- PAWN program builder helpers ---- */

/* Append a 64-bit instruction to a growing vector. */
static inline void emit(std::vector<uint64_t> &p, uint64_t instr)
{
    p.push_back(instr);
}

/* Build GEMM program into prog.
 *
 * DBRAM layout (fixed, uses TM/TN/TK even at boundary -- caller pads with zeros):
 *   [0 .. TM*TK-1]              A_tile  (TM rows x TK cols, row-major)
 *   [TM*TK .. TM*TK+TK*TN-1]   B_tile  (TK rows x TN cols, row-major)
 *   [TM*TK+TK*TN .. +TM*TN-1]  C_tile  (TM rows x TN cols, row-major)
 *   [TM*TK+TK*TN+TM*TN]        TMP     (one word; only used in no-quire mode)
 *
 * is_first_k: for quire mode: emit QCLR only (no reload of C).
 *             for no-quire mode: initialize C from first MUL (no ADD on k=0).
 */
static void build_gemm_prog(std::vector<uint64_t> &prog,
                             int TM, int TN, int TK,
                             bool is_first_k, bool use_quire)
{
    prog.clear();
    int BASE_A   = 0;
    int BASE_B   = TM * TK;
    int BASE_C   = TM * TK + TK * TN;
    int BASE_TMP = BASE_C + TM * TN;

    for (int i = 0; i < TM; i++) {
        for (int j = 0; j < TN; j++) {
            int addr_c = BASE_C + i*TN + j;
            if (use_quire) {
                emit(prog, PAWN_INSTR(PAWN_OP_QACC_CLEAR, 0, 0, 0));
                if (!is_first_k)
                    emit(prog, PAWN_INSTR(PAWN_OP_QACC_ADD, addr_c, 0, 0));
                for (int k = 0; k < TK; k++)
                    emit(prog, PAWN_INSTR(PAWN_OP_QACC_MADD,
                                          BASE_A + i*TK + k,
                                          BASE_B + k*TN + j, 0));
                emit(prog, PAWN_INSTR(PAWN_OP_QACC_READ, 0, 0, addr_c));
            } else {
                if (is_first_k) {
                    emit(prog, PAWN_INSTR(PAWN_OP_MUL,
                                          BASE_A + i*TK,
                                          BASE_B + j, addr_c));
                    for (int k = 1; k < TK; k++) {
                        emit(prog, PAWN_INSTR(PAWN_OP_MUL,
                                              BASE_A + i*TK + k,
                                              BASE_B + k*TN + j, BASE_TMP));
                        emit(prog, PAWN_INSTR(PAWN_OP_ADD, addr_c, BASE_TMP, addr_c));
                    }
                } else {
                    for (int k = 0; k < TK; k++) {
                        emit(prog, PAWN_INSTR(PAWN_OP_MUL,
                                              BASE_A + i*TK + k,
                                              BASE_B + k*TN + j, BASE_TMP));
                        emit(prog, PAWN_INSTR(PAWN_OP_ADD, addr_c, BASE_TMP, addr_c));
                    }
                }
            }
        }
    }
    emit(prog, PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0));
}

/* Build conv program for NTILE output pixels, each accumulated over KA filter taps.
 *
 * DBRAM layout:
 *   [0 .. KA-1]                        filter (flat, KA words)
 *   [KA .. KA+NTILE*KA-1]              im2col patches (NTILE rows x KA cols, row-major)
 *   [KA+NTILE*KA .. KA+NTILE*KA+NTILE-1]  output (NTILE words)
 *   [KA+NTILE*KA+NTILE]                TMP (no-quire only)
 */
static void build_conv_prog(std::vector<uint64_t> &prog,
                             int NTILE, int KA,
                             bool is_first_k, bool use_quire)
{
    prog.clear();
    int BASE_FILT = 0;
    int BASE_PATCH = KA;
    int BASE_OUT   = KA + NTILE * KA;
    int BASE_TMP   = BASE_OUT + NTILE;

    for (int p = 0; p < NTILE; p++) {
        int addr_out = BASE_OUT + p;
        if (use_quire) {
            emit(prog, PAWN_INSTR(PAWN_OP_QACC_CLEAR, 0, 0, 0));
            if (!is_first_k)
                emit(prog, PAWN_INSTR(PAWN_OP_QACC_ADD, addr_out, 0, 0));
            for (int k = 0; k < KA; k++)
                emit(prog, PAWN_INSTR(PAWN_OP_QACC_MADD,
                                      BASE_PATCH + p*KA + k,
                                      BASE_FILT + k, 0));
            emit(prog, PAWN_INSTR(PAWN_OP_QACC_READ, 0, 0, addr_out));
        } else {
            if (is_first_k) {
                emit(prog, PAWN_INSTR(PAWN_OP_MUL,
                                      BASE_PATCH + p*KA,
                                      BASE_FILT, addr_out));
                for (int k = 1; k < KA; k++) {
                    emit(prog, PAWN_INSTR(PAWN_OP_MUL,
                                          BASE_PATCH + p*KA + k,
                                          BASE_FILT + k, BASE_TMP));
                    emit(prog, PAWN_INSTR(PAWN_OP_ADD, addr_out, BASE_TMP, addr_out));
                }
            } else {
                for (int k = 0; k < KA; k++) {
                    emit(prog, PAWN_INSTR(PAWN_OP_MUL,
                                          BASE_PATCH + p*KA + k,
                                          BASE_FILT + k, BASE_TMP));
                    emit(prog, PAWN_INSTR(PAWN_OP_ADD, addr_out, BASE_TMP, addr_out));
                }
            }
        }
    }
    emit(prog, PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0));
}

/* ---- arg parsing helpers ---- */

static bool arg_flag(int argc, char *argv[], const char *flag)
{
    for (int i = 1; i < argc; i++)
        if (strcmp(argv[i], flag) == 0) return true;
    return false;
}

static const char *arg_str(int argc, char *argv[], const char *opt, const char *def)
{
    for (int i = 1; i < argc - 1; i++)
        if (strcmp(argv[i], opt) == 0) return argv[i+1];
    return def;
}

static int arg_int(int argc, char *argv[], const char *opt, int def)
{
    const char *s = arg_str(argc, argv, opt, nullptr);
    return s ? atoi(s) : def;
}

/* ---- timing report ---- */

static void print_timing(double load_ms, double compute_ms, double readback_ms,
                         double sw_ms, int total_tiles, long long total_bytes_load,
                         long long total_bytes_read, bool k_tiling_active,
                         bool use_quire)
{
    printf("  Mode: %s\n", use_quire ? "quire" : "no-quire (plain MUL+ADD)");
    if (k_tiling_active)
        printf("  NOTE: K-tiling active -- quire rounded at tile boundaries\n");
    printf("  Tiles: %d executions\n", total_tiles);
    printf("\n");
    printf("  PAWN accelerator:\n");
    double load_bw   = load_ms   > 0 ? (double)total_bytes_load  / (load_ms   * 1e3) : 0;
    double read_bw   = readback_ms > 0 ? (double)total_bytes_read / (readback_ms * 1e3) : 0;
    printf("    Data load:     %8.3f ms  (%.1f MB/s)\n", load_ms, load_bw);
    printf("    Compute:       %8.3f ms\n", compute_ms);
    printf("    Data readback: %8.3f ms  (%.1f MB/s)\n", readback_ms, read_bw);
    printf("    Total:         %8.3f ms\n", load_ms + compute_ms + readback_ms);
    printf("\n");
    printf("  libpawn reference:\n");
    printf("    Total:         %8.3f ms\n", sw_ms);
    if (sw_ms > 0) {
        printf("\n");
        printf("  Speedup (compute only): %.2fx\n", sw_ms / compute_ms);
        printf("  Speedup (total):        %.2fx\n", sw_ms / (load_ms + compute_ms + readback_ms));
    }
}
