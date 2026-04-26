/*
 * pawn.h -- PAWN accelerator userspace driver
 *
 * Targets: Zedboard PetaLinux (ARMv7), /dev/mem mmap.
 *
 * AXI-Lite slave:  0x43C00000 (GP0, 64 KiB) -- control, IBRAM, DBRAM single-word
 * AXI burst slave: 0x80000000 (GP1, 64 KiB) -- DBRAM bulk read/write
 *
 * ---- Host data representation ("upper-bits" convention) ----
 *
 * Posit values are stored left-aligned in the host element type so that the
 * same bit pattern is valid across widths:
 *
 *   DATA_WIDTH=8:   posit8  encoding in bits [31:24] of uint32_t
 *   DATA_WIDTH=16:  posit16 encoding in bits [31:16] of uint32_t
 *   DATA_WIDTH=32:  posit32 encoding in all 32 bits  of uint32_t
 *   DATA_WIDTH=64:  posit64 encoding in all 64 bits  of uint64_t
 *
 * Example: posit 1.0 is 0x40000000 for DATA_WIDTH 8, 16, and 32 alike
 * (posit<8,2> 1.0 = 0x40 sits in bits [31:24]; posit<32,2> 1.0 = 0x40000000).
 * A program written for posit32 runs for posit8/16 without any code change --
 * just call the right-width dbram_write/read pair; the driver shifts in/out.
 *
 * ---- Addressing ----
 *
 * All dbram functions take a 'base' word index (0 .. DATA_DEPTH-1).
 * For the burst slave:
 *   8/16/32-bit: one 32-bit AXI beat per BRAM word (stride = 4 bytes)
 *   64-bit:      two 32-bit AXI beats per BRAM word (lo then hi, stride = 8 bytes)
 */

#ifndef PAWN_H
#define PAWN_H

#include <stdint.h>
#include <stddef.h>

/* ---- Physical addresses ---- */
#define PAWN_BASE_LITE   0x43C00000UL
#define PAWN_BASE_BURST  0x80000000UL
#define PAWN_MAP_SIZE    0x10000UL     /* 64 KiB */

/* ---- Register offsets (AXI-Lite, byte offsets from PAWN_BASE_LITE) ---- */
#define PAWN_REG_CTRL          0x00  /* [0]=START, [1]=RESET (self-clearing)      */
#define PAWN_REG_STATUS        0x04  /* [0]=DONE,  [1]=RUNNING (read-only)         */
#define PAWN_REG_IBRAM_ADDR    0x08  /* instruction BRAM word index                */
#define PAWN_REG_IBRAM_DATA_LO 0x0C  /* instr bits [31:0]                          */
#define PAWN_REG_IBRAM_DATA_HI 0x10  /* instr bits [63:32]; write triggers BRAM WE */
#define PAWN_REG_DBRAM_ADDR    0x14  /* data BRAM word index (explicit set)         */
#define PAWN_REG_DBRAM_DATA    0x18  /* DBRAM [DATA_WIDTH-1:0]; write/read -> +1   */
                                     /* auto-increments for DATA_WIDTH <= 32        */
#define PAWN_REG_DBRAM_DATA_HI 0x1C  /* DBRAM [63:32] (64-bit only);               */
                                     /* write triggers BRAM WE + addr auto-inc      */

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
 * Encode one 64-bit instruction:
 *   [63:60] opcode   [59:40] addr_a   [39:20] addr_b   [19:0] addr_result
 */
#define PAWN_INSTR(op, a, b, r) \
    ( ((uint64_t)(op) << 60) | \
      ((uint64_t)(a)  << 40) | \
      ((uint64_t)(b)  << 20) | \
      ((uint64_t)(r)       ) )

/* ---- Device handle ---- */
typedef struct {
    volatile uint32_t *lite;    /* mmap of AXI-Lite slave  (0x43C00000) */
    volatile uint32_t *burst;   /* mmap of AXI burst slave (0x80000000) */
    int                devmem_fd;
} pawn_dev_t;

/* ---- Lifecycle ---- */
int  pawn_open (pawn_dev_t *dev);   /* open /dev/mem, mmap both regions */
void pawn_close(pawn_dev_t *dev);   /* unmap + close                    */
void pawn_reset(pawn_dev_t *dev);   /* synchronous core reset           */

/* ---- Program load ---- */
/*
 * Write 'count' instructions to IBRAM starting at word 0.
 * Last instruction must be PAWN_INSTR(PAWN_OP_HALT, 0, 0, 0).
 * Returns 0 on success, -1 if count > IBRAM_DEPTH (2^15).
 */
int pawn_load_program(pawn_dev_t *dev, const uint64_t *instrs, size_t count);

/* ---- DBRAM bulk read/write via AXI burst slave ---- */
/*
 * Each function writes/reads 'count' BRAM words starting at word index 'base'.
 *
 * 8-bit:  host uint32_t has posit8  encoding in bits [31:24]; driver shifts >> 24
 * 16-bit: host uint32_t has posit16 encoding in bits [31:16]; driver shifts >> 16
 * 32-bit: host uint32_t is the full posit32 encoding; no shift
 * 64-bit: host uint64_t is the full posit64 encoding; written as lo then hi beat
 */
void pawn_dbram_write8 (pawn_dev_t *dev, uint32_t base, const uint32_t *data, size_t count);
void pawn_dbram_write16(pawn_dev_t *dev, uint32_t base, const uint32_t *data, size_t count);
void pawn_dbram_write32(pawn_dev_t *dev, uint32_t base, const uint32_t *data, size_t count);
void pawn_dbram_write64(pawn_dev_t *dev, uint32_t base, const uint64_t *data, size_t count);

void pawn_dbram_read8 (pawn_dev_t *dev, uint32_t base, uint32_t *data, size_t count);
void pawn_dbram_read16(pawn_dev_t *dev, uint32_t base, uint32_t *data, size_t count);
void pawn_dbram_read32(pawn_dev_t *dev, uint32_t base, uint32_t *data, size_t count);
void pawn_dbram_read64(pawn_dev_t *dev, uint32_t base, uint64_t *data, size_t count);

/* ---- DBRAM single-word access via AXI-Lite PIO ---- */
/*
 * Use for sparse / debug access.  Slower than burst (one AXI transaction each).
 * Same upper-bits convention applies to the 8/16/32-bit variants.
 * Address auto-increment is NOT used; 'idx' is always written to DBRAM_ADDR.
 */
void     pawn_dbram_poke8 (pawn_dev_t *dev, uint32_t idx, uint32_t val);
uint32_t pawn_dbram_peek8 (pawn_dev_t *dev, uint32_t idx);
void     pawn_dbram_poke16(pawn_dev_t *dev, uint32_t idx, uint32_t val);
uint32_t pawn_dbram_peek16(pawn_dev_t *dev, uint32_t idx);
void     pawn_dbram_poke32(pawn_dev_t *dev, uint32_t idx, uint32_t val);
uint32_t pawn_dbram_peek32(pawn_dev_t *dev, uint32_t idx);
void     pawn_dbram_poke64(pawn_dev_t *dev, uint32_t idx, uint64_t val);
uint64_t pawn_dbram_peek64(pawn_dev_t *dev, uint32_t idx);

/* ---- Execution ---- */
void      pawn_start(pawn_dev_t *dev);                          /* non-blocking          */
int       pawn_done (pawn_dev_t *dev);                          /* non-zero when halted  */
uint32_t  pawn_status(pawn_dev_t *dev);                         /* raw STATUS register   */
long long pawn_run_blocking(pawn_dev_t *dev, unsigned timeout_ms); /* start+wait, returns ns */

#endif /* PAWN_H */
