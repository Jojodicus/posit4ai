/*
 * pawn.h -- PAWN accelerator userspace driver
 *
 * Targets: Zedboard PetaLinux (ARMv7), /dev/mem mmap.
 *
 * AXI-Lite slave:   0x43C00000  (GP0, 64 KiB) -- control + IBRAM + DBRAM PIO
 * AXI burst slave:  0x80000000  (GP1, 64 KiB) -- DBRAM bulk read/write
 */

#ifndef PAWN_H
#define PAWN_H

#include <stdint.h>
#include <stddef.h>

/* ---- Register offsets (AXI-Lite base 0x43C00000) ---- */
#define PAWN_BASE_LITE   0x43C00000UL
#define PAWN_BASE_BURST  0x80000000UL
#define PAWN_MAP_SIZE    0x10000UL   /* 64 KiB */

#define PAWN_REG_CTRL          0x00  /* [0]=START, [1]=RESET (self-clearing) */
#define PAWN_REG_STATUS        0x04  /* [0]=DONE,  [1]=RUNNING (read-only)   */
#define PAWN_REG_IBRAM_ADDR    0x08  /* instruction BRAM word index           */
#define PAWN_REG_IBRAM_DATA_LO 0x0C  /* instr bits [31:0]                    */
#define PAWN_REG_IBRAM_DATA_HI 0x10  /* instr bits [63:32]; write -> BRAM WE */
#define PAWN_REG_DBRAM_ADDR    0x14  /* data BRAM word index (auto-incr)      */
#define PAWN_REG_DBRAM_DATA    0x18  /* data BRAM [31:0]; write/read -> +1   */
#define PAWN_REG_DBRAM_DATA_HI 0x1C  /* data BRAM [63:32] (DATA_WIDTH=64)    */

#define PAWN_STATUS_DONE    (1u << 0)
#define PAWN_STATUS_RUNNING (1u << 1)

/* ---- Opcodes ---- */
#define PAWN_OP_HALT       0x0
#define PAWN_OP_ADD        0x1
#define PAWN_OP_SUB        0x2
#define PAWN_OP_MUL        0x3
#define PAWN_OP_DIV        0x4
#define PAWN_OP_SQRT       0x5
#define PAWN_OP_NEG        0x6
#define PAWN_OP_ABS        0x7
#define PAWN_OP_MOV        0x8
#define PAWN_OP_RELU       0x9
#define PAWN_OP_QACC_CLEAR 0xA
#define PAWN_OP_QACC_ADD   0xB
#define PAWN_OP_QACC_MADD  0xC
#define PAWN_OP_QACC_MSUB  0xD
#define PAWN_OP_QACC_NEG   0xE
#define PAWN_OP_QACC_READ  0xF

/*
 * Instruction encoding: 64-bit
 *   [63:60] opcode (4b)
 *   [59:40] addr_a (20b)
 *   [39:20] addr_b (20b)
 *   [19: 0] addr_result (20b)
 */
#define PAWN_INSTR(op, a, b, r) \
    ( ((uint64_t)(op)  << 60) | \
      ((uint64_t)(a)   << 40) | \
      ((uint64_t)(b)   << 20) | \
      ((uint64_t)(r)        ) )

/* ---- Device handle ---- */
typedef struct {
    volatile uint32_t *lite;   /* mmap'd AXI-Lite region */
    volatile uint32_t *burst;  /* mmap'd AXI burst region */
    int               devmem_fd;
} pawn_dev_t;

/* ---- API ---- */

/* Open /dev/mem and mmap both AXI regions. Returns 0 on success. */
int pawn_open(pawn_dev_t *dev);

/* Unmap regions and close /dev/mem. */
void pawn_close(pawn_dev_t *dev);

/* Reset the accelerator core (synchronous; clears DONE). */
void pawn_reset(pawn_dev_t *dev);

/*
 * Write instructions to IBRAM starting at word index 0.
 * instrs[i] is the 64-bit encoded instruction (use PAWN_INSTR macro).
 * The last instruction in the program should be PAWN_INSTR(PAWN_OP_HALT,0,0,0).
 * Returns 0 on success, -1 if count is out of range.
 */
int pawn_load_program(pawn_dev_t *dev, const uint64_t *instrs, size_t count);

/*
 * Bulk-write 'count' 32-bit data words to DBRAM starting at index 'base'.
 * Uses the AXI burst slave (GP1) -- much faster than PIO for large arrays.
 */
void pawn_dbram_write(pawn_dev_t *dev, uint32_t base, const uint32_t *data,
                      size_t count);

/*
 * Bulk-read 'count' 32-bit data words from DBRAM starting at index 'base'.
 * Uses the AXI burst slave (GP1).
 */
void pawn_dbram_read(pawn_dev_t *dev, uint32_t base, uint32_t *data,
                     size_t count);

/*
 * Start the accelerator and block until DONE.
 * Returns elapsed time in nanoseconds (via CLOCK_MONOTONIC).
 * Timeout of 0 means wait indefinitely.
 */
long long pawn_run_blocking(pawn_dev_t *dev, unsigned timeout_ms);

/* Non-blocking start (returns immediately). */
void pawn_start(pawn_dev_t *dev);

/* Poll status. Returns non-zero if DONE. */
int pawn_done(pawn_dev_t *dev);

/* Read raw STATUS register. */
uint32_t pawn_status(pawn_dev_t *dev);

#endif /* PAWN_H */
