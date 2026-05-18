/*
 * server.c  --  SmallNet FPGA inference server
 *
 * HTTP API:
 *   GET  /health   -> {"status":"ok"}
 *   POST /weights  -> binary body: uint32_t[25450] posit32<es=2> row-major
 *                    order: fc1_weight[32x784], fc1_bias[32],
 *                           fc2_weight[10x32], fc2_bias[10]
 *   POST /infer    -> binary body: uint32_t[784] posit32<es=2> pixel values
 *                    response: {"class":N,"time_us":T}
 *
 * All uint32_t values are posit<32,2> in native 32-bit encoding (left-aligned
 * in the BRAM word).  An 8-bit bitstream reads the top 8 bits automatically.
 * Argmax uses int32_t comparison, which is correct for all posit widths.
 *
 * One combined program (FC1 then FC2, single HALT) is built at startup and
 * loaded once per inference.  FC1_BASE_OUT == FC2_BASE_IN so the hidden layer
 * stays in DBRAM with no CPU roundtrip between layers.
 *
 * DBRAM layout (26276 words total, limit 32768):
 *   [0      ] FC1 input  (784)
 *   [784    ] FC1 weight (784x32 = 25088, transposed)
 *   [25872  ] FC1 bias   (32)
 *   [25904  ] FC1 output = FC2 input (32)
 *   [25936  ] FC2 weight (32x10 = 320, transposed)
 *   [26256  ] FC2 output / logits (10)
 *   [26266  ] FC2 bias   (10)
 *
 * Combined program: 25609 instructions (limit 32768).
 *
 * Cross-compile:
 *   arm-linux-gnueabihf-gcc -O2 -Wall -std=c11 -static \
 *       -o server server.c ../../PAWN/sw/pawn.c -I../../PAWN/sw
 */

#define _POSIX_C_SOURCE 200809L
#include "pawn.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

/* ---- model dimensions ---- */
#define FC1_IN    784
#define FC1_OUT    32
#define FC2_IN     32
#define FC2_OUT    10

/* FC1: all 32 neurons in one pass (no N-tiling), K=784 fits without K-tiling.
 * FC2: 10 neurons, K=32. */
#define FC1_TN        FC1_OUT    /* 32 */
#define FC1_TK        FC1_IN     /* 784 */

#define FC2_TN        FC2_OUT    /* 10 */
#define FC2_TK        FC2_IN     /* 32 */

/* ---- combined DBRAM layout ---- */
/* Bias placed before output so FC1_BASE_OUT == FC2_BASE_IN (no CPU roundtrip). */
#define FC1_BASE_IN    0
#define FC1_BASE_W    (FC1_TK)                        /* 784   */
#define FC1_BASE_BIAS (FC1_BASE_W  + FC1_TK * FC1_TN) /* 25872 */
#define FC1_BASE_OUT  (FC1_BASE_BIAS + FC1_TN)         /* 25904 */

#define FC2_BASE_IN    FC1_BASE_OUT                    /* 25904 */
#define FC2_BASE_W    (FC2_BASE_IN + FC2_TK)           /* 25936 */
#define FC2_BASE_OUT  (FC2_BASE_W  + FC2_TK * FC2_TN)  /* 26256 */
#define FC2_BASE_BIAS (FC2_BASE_OUT + FC2_TN)           /* 26266 */

/* ---- combined program size upper bound ---- */
/* FC1 (no HALT): TN*(TK+3) + TN ADD + TN RELU                    = 25248 */
/* FC2 (HALT):    TN*(TK+3) + TN ADD + HALT                       =   361 */
#define COMBINED_PROG_MAX  (FC1_TN * (FC1_TK + 3) + FC1_TN * 2 + \
                            FC2_TN * (FC2_TK + 3) + FC2_TN     + 2)

/* ---- weight counts ---- */
#define W_FC1_W  (FC1_OUT * FC1_IN)   /* 25088 */
#define W_FC1_B  FC1_OUT               /*    32 */
#define W_FC2_W  (FC2_OUT * FC2_IN)   /*   320 */
#define W_FC2_B  FC2_OUT               /*    10 */
#define W_TOTAL  (W_FC1_W + W_FC1_B + W_FC2_W + W_FC2_B)   /* 25450 */

#define WEIGHTS_BYTES  (W_TOTAL  * 4)   /* 101800 */
#define INFER_BYTES    (FC1_IN   * 4)   /*   3136 */

/* ---- global state ---- */
static uint32_t  g_fc1_w[W_FC1_W];
static uint32_t  g_fc1_b[W_FC1_B];
static uint32_t  g_fc2_w[W_FC2_W];
static uint32_t  g_fc2_b[W_FC2_B];
static int       g_weights_loaded = 0;

static uint64_t  g_combined_prog[COMBINED_PROG_MAX];
static size_t    g_combined_prog_len;
static int       g_prog_loaded = 0;

static pawn_dev_t g_dev;

/* Scratch buffers: g_wtile is large enough for the FC1 weight transpose (25088).
 * Reused (after the FC1 write) for the smaller FC2 weight transpose (320). */
static uint32_t  g_wtile[FC1_TK * FC1_TN];
static uint32_t  g_logits[FC2_OUT];

/* ---- timing ---- */
static long long now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

/* ---- program builder ---- */

/*
 * Combined FC1+FC2 program.  FC1 runs without HALT; execution falls through
 * directly into FC2, which ends with HALT.  FC1_BASE_OUT == FC2_BASE_IN so
 * the hidden layer is consumed in-place with no CPU roundtrip.
 *
 * FC1: GEMM (quire) + bias ADD + ReLU  (32 neurons, K=784)
 * FC2: GEMM (quire) + bias ADD         (10 neurons, K=32, no ReLU)
 */
static size_t build_combined_prog(uint64_t *prog)
{
    size_t n = 0;

    /* FC1 GEMM + bias + ReLU */
    for (int j = 0; j < FC1_TN; j++) {
        prog[n++] = PAWN_INSTR(PAWN_OP_QACC_CLEAR, 0, 0, 0);
        prog[n++] = PAWN_INSTR(PAWN_OP_QACC_CLEAR, 0, 0, 0);
        for (int k = 0; k < FC1_TK; k++)
            prog[n++] = PAWN_INSTR(PAWN_OP_QACC_MADD,
                                   FC1_BASE_IN + k,
                                   FC1_BASE_W  + k * FC1_TN + j, 0);
        prog[n++] = PAWN_INSTR(PAWN_OP_QACC_READ, 0, 0, FC1_BASE_OUT + j);
    }
    for (int j = 0; j < FC1_TN; j++)
        prog[n++] = PAWN_INSTR(PAWN_OP_ADD,
                               FC1_BASE_OUT + j, FC1_BASE_BIAS + j,
                               FC1_BASE_OUT + j);
    for (int j = 0; j < FC1_TN; j++)
        prog[n++] = PAWN_INSTR(PAWN_OP_RELU, FC1_BASE_OUT + j, 0,
                               FC1_BASE_OUT + j);
    /* no HALT: fall through into FC2 */

    /* FC2 GEMM + bias (no ReLU) */
    for (int j = 0; j < FC2_TN; j++) {
        prog[n++] = PAWN_INSTR(PAWN_OP_QACC_CLEAR, 0, 0, 0);
        prog[n++] = PAWN_INSTR(PAWN_OP_QACC_CLEAR, 0, 0, 0);
        for (int k = 0; k < FC2_TK; k++)
            prog[n++] = PAWN_INSTR(PAWN_OP_QACC_MADD,
                                   FC2_BASE_IN + k,
                                   FC2_BASE_W  + k * FC2_TN + j, 0);
        prog[n++] = PAWN_INSTR(PAWN_OP_QACC_READ, 0, 0, FC2_BASE_OUT + j);
    }
    for (int j = 0; j < FC2_TN; j++)
        prog[n++] = PAWN_INSTR(PAWN_OP_ADD,
                               FC2_BASE_OUT + j, FC2_BASE_BIAS + j,
                               FC2_BASE_OUT + j);
    prog[n++] = PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0);
    return n;
}

/* ---- inference ---- */

/*
 * Run one SmallNet forward pass.
 * input:       FC1_IN uint32_t posit32 values (pixel data, MNIST-normalized)
 * cls:         output predicted class [0..9]
 * time_us:     total wall-clock time in microseconds
 * load_us:     DBRAM write time (input + weights)
 * compute_us:  PAWN execution time (from pawn_run_blocking return value, ns->us)
 * read_us:     DBRAM read time (logits)
 * Returns 0 on success, -1 if no weights, -2 on PAWN timeout.
 */
static int run_inference(const uint32_t *input, int *cls,
                         long long *time_us, long long *load_us,
                         long long *compute_us, long long *read_us)
{
    if (!g_weights_loaded)
        return -1;

    long long wall0 = now_ns();

    /* ---- DBRAM load ---- */
    long long t0 = now_ns();

    /*
     * Transpose FC1 weights into DBRAM layout B[k][j] = weight[j][k].
     * (GEMM: C[j] = sum_k A[k] * B[k][j]  where  B[k][j] = W[j][k])
     */
    for (int k = 0; k < FC1_TK; k++)
        for (int j = 0; j < FC1_TN; j++)
            g_wtile[k * FC1_TN + j] = g_fc1_w[j * FC1_IN + k];

    pawn_dbram_write32(&g_dev, FC1_BASE_IN,   input,    FC1_TK);
    pawn_dbram_write32(&g_dev, FC1_BASE_W,    g_wtile,  FC1_TK * FC1_TN);
    pawn_dbram_write32(&g_dev, FC1_BASE_BIAS, g_fc1_b,  FC1_TN);

    /* Transpose FC2 weights; reuse g_wtile (FC1 data already written to DBRAM). */
    for (int k = 0; k < FC2_TK; k++)
        for (int j = 0; j < FC2_TN; j++)
            g_wtile[k * FC2_TN + j] = g_fc2_w[j * FC2_IN + k];

    pawn_dbram_write32(&g_dev, FC2_BASE_W,    g_wtile,  FC2_TK * FC2_TN);
    pawn_dbram_write32(&g_dev, FC2_BASE_BIAS, g_fc2_b,  FC2_TN);

    *load_us = (now_ns() - t0) / 1000;

    /* ---- program (only if IBRAM was cleared by a prior reset) ---- */
    if (!g_prog_loaded) {
        pawn_load_program(&g_dev, g_combined_prog, g_combined_prog_len);
        g_prog_loaded = 1;
    }

    /* ---- compute ---- */
    long long ns = pawn_run_blocking(&g_dev, 30000);
    if (ns < 0) {
        pawn_reset(&g_dev);
        g_prog_loaded = 0;
        return -2;
    }
    *compute_us = ns / 1000;

    /* ---- DBRAM readback ---- */
    t0 = now_ns();
    pawn_dbram_read32(&g_dev, FC2_BASE_OUT, g_logits, FC2_TN);
    *read_us = (now_ns() - t0) / 1000;

    /*
     * Argmax using int32_t comparison.
     * Posit values are left-aligned in the 32-bit DBRAM word, so comparing as
     * signed 32-bit integers gives the correct posit ordering for all bitstream
     * widths (8/16/32 bit).  NaR (0x80000000 = INT32_MIN) is always lowest.
     */
    int best = 0;
    int32_t best_v = (int32_t)g_logits[0];
    for (int i = 1; i < FC2_OUT; i++) {
        int32_t v = (int32_t)g_logits[i];
        if (v > best_v) { best_v = v; best = i; }
    }
    *cls = best;
    *time_us = (now_ns() - wall0) / 1000;
    return 0;
}

/* ---- HTTP helpers ---- */

static void write_all(int fd, const void *buf, size_t n)
{
    size_t done = 0;
    while (done < n) {
        ssize_t r = write(fd, (const char *)buf + done, n - done);
        if (r <= 0) return;
        done += (size_t)r;
    }
}

static void send_json(int fd, int status, const char *body)
{
    const char *s = status == 200 ? "OK"
                  : status == 400 ? "Bad Request"
                  : status == 503 ? "Service Unavailable"
                  :                 "Internal Server Error";
    char hdr[256];
    int hlen = snprintf(hdr, sizeof(hdr),
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n"
        "\r\n",
        status, s, strlen(body));
    write_all(fd, hdr, (size_t)hlen);
    write_all(fd, body, strlen(body));
}

/* Read HTTP headers byte-by-byte until \r\n\r\n.  Returns total bytes or -1. */
#define HDR_MAX 2048
static char g_hdr[HDR_MAX];

static int read_headers(int fd)
{
    int n = 0;
    while (n < HDR_MAX - 1) {
        if (read(fd, g_hdr + n, 1) != 1) return -1;
        n++;
        g_hdr[n] = '\0';
        if (n >= 4 && memcmp(g_hdr + n - 4, "\r\n\r\n", 4) == 0)
            return n;
    }
    return -1;
}

static int read_exact(int fd, void *buf, size_t n)
{
    size_t done = 0;
    while (done < n) {
        ssize_t r = read(fd, (char *)buf + done, n - done);
        if (r <= 0) return -1;
        done += (size_t)r;
    }
    return 0;
}

/* Case-insensitive search for Content-Length value in header buffer. */
static size_t parse_content_length(const char *hdrs)
{
    /* Lower-case copy for searching */
    char lower[HDR_MAX];
    size_t i;
    for (i = 0; hdrs[i] && i < HDR_MAX - 1; i++)
        lower[i] = (hdrs[i] >= 'A' && hdrs[i] <= 'Z')
                   ? (char)(hdrs[i] + 32) : hdrs[i];
    lower[i] = '\0';

    const char *p = strstr(lower, "content-length:");
    if (!p) return 0;
    /* Skip optional whitespace */
    p += 15;
    while (*p == ' ' || *p == '\t') p++;
    return (size_t)atol(p);
}

/* ---- request handler ---- */

static void handle_request(int fd)
{
    if (read_headers(fd) < 0) return;

    char method[8] = {0}, path[64] = {0};
    if (sscanf(g_hdr, "%7s %63s", method, path) != 2) return;

    size_t clen = parse_content_length(g_hdr);

    /* GET /health */
    if (strcmp(method, "GET") == 0 && strcmp(path, "/health") == 0) {
        send_json(fd, 200, "{\"status\":\"ok\"}");
        return;
    }

    /* POST /weights */
    if (strcmp(method, "POST") == 0 && strcmp(path, "/weights") == 0) {
        if (clen != WEIGHTS_BYTES) {
            fprintf(stderr, "weights: bad size %zu (want %d)\n",
                    clen, WEIGHTS_BYTES);
            send_json(fd, 400, "{\"error\":\"wrong body size\"}");
            return;
        }
        uint8_t *body = malloc(WEIGHTS_BYTES);
        if (!body) { send_json(fd, 500, "{\"error\":\"oom\"}"); return; }
        if (read_exact(fd, body, WEIGHTS_BYTES) != 0) {
            free(body);
            send_json(fd, 500, "{\"error\":\"read failed\"}");
            return;
        }
        const uint32_t *p32 = (const uint32_t *)body;
        memcpy(g_fc1_w, p32,                       W_FC1_W * 4);
        memcpy(g_fc1_b, p32 + W_FC1_W,             W_FC1_B * 4);
        memcpy(g_fc2_w, p32 + W_FC1_W + W_FC1_B,   W_FC2_W * 4);
        memcpy(g_fc2_b, p32 + W_FC1_W + W_FC1_B + W_FC2_W, W_FC2_B * 4);
        free(body);
        g_weights_loaded = 1;
        printf("Weights loaded (%d uint32 values).\n", W_TOTAL);
        fflush(stdout);
        send_json(fd, 200, "{\"status\":\"ok\"}");
        return;
    }

    /* POST /infer */
    if (strcmp(method, "POST") == 0 && strcmp(path, "/infer") == 0) {
        if (!g_weights_loaded) {
            send_json(fd, 503, "{\"error\":\"weights not loaded\"}");
            return;
        }
        if (clen != INFER_BYTES) {
            send_json(fd, 400, "{\"error\":\"wrong body size\"}");
            return;
        }
        uint32_t input[FC1_IN];
        if (read_exact(fd, input, INFER_BYTES) != 0) {
            send_json(fd, 500, "{\"error\":\"read failed\"}");
            return;
        }
        int cls;
        long long time_us, load_us, compute_us, read_us;
        int rc = run_inference(input, &cls, &time_us, &load_us, &compute_us, &read_us);
        if (rc == -1) {
            send_json(fd, 503, "{\"error\":\"weights not loaded\"}");
        } else if (rc == -2) {
            send_json(fd, 500, "{\"error\":\"pawn timeout\"}");
        } else {
            char resp[192];
            snprintf(resp, sizeof(resp),
                     "{\"class\":%d,\"time_us\":%lld"
                     ",\"load_us\":%lld,\"compute_us\":%lld,\"read_us\":%lld}",
                     cls, time_us, load_us, compute_us, read_us);
            send_json(fd, 200, resp);
        }
        return;
    }

    send_json(fd, 404, "{\"error\":\"not found\"}");
}

/* ---- main ---- */

int main(int argc, char *argv[])
{
    int port = (argc > 1) ? atoi(argv[1]) : 8080;

    printf("Opening PAWN device...\n");
    if (pawn_open(&g_dev) != 0) {
        fprintf(stderr, "pawn_open failed\n");
        return 1;
    }
    pawn_reset(&g_dev);
    printf("PAWN ready.\n");

    /* Build and load combined program once; IBRAM retains it across all inferences.
     * g_prog_loaded is cleared to 0 if pawn_reset is called after a timeout. */
    g_combined_prog_len = build_combined_prog(g_combined_prog);
    printf("Combined program built: %zu instrs\n", g_combined_prog_len);
    pawn_load_program(&g_dev, g_combined_prog, g_combined_prog_len);
    g_prog_loaded = 1;

    int srv = socket(AF_INET, SOCK_STREAM, 0);
    if (srv < 0) { perror("socket"); pawn_close(&g_dev); return 1; }

    int opt = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port   = htons((uint16_t)port),
        .sin_addr   = { .s_addr = htonl(INADDR_ANY) },
    };
    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) != 0 ||
        listen(srv, 4) != 0) {
        perror("bind/listen");
        pawn_close(&g_dev);
        return 1;
    }
    printf("Listening on 0.0.0.0:%d\n", port);
    printf("POST /weights to load weights, POST /infer to run inference.\n");
    fflush(stdout);

    while (1) {
        struct sockaddr_in cli;
        socklen_t cli_len = sizeof(cli);
        int fd = accept(srv, (struct sockaddr *)&cli, &cli_len);
        if (fd < 0) continue;
        handle_request(fd);
        close(fd);
    }

    pawn_close(&g_dev);
    return 0;
}
