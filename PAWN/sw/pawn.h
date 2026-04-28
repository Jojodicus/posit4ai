/*
 * pawn.h -- PAWN accelerator userspace driver (Zedboard PetaLinux, /dev/mem)
 *
 * AXI-Lite slave:  0x43C00000 (GP0) -- control, IBRAM, DBRAM single-word
 * AXI burst slave: 0x80000000 (GP1) -- DBRAM bulk read/write
 *
 * Data convention: the RTL stores posit values left-aligned in the BRAM word,
 * extracting the high DATA_WIDTH bits from each 32-bit AXI write and returning
 * them left-aligned on read.  Host arrays are uint32_t for DATA_WIDTH 8/16/32,
 * uint64_t for 64.  posit 1.0 = 0x40000000 for all of 8, 16, 32-bit widths.
 *
 * For raw sub-32 posit values use PAWN_PACK / PAWN_UNPACK:
 *   pawn_dbram_write32(dev, 0, (uint32_t[]){ PAWN_PACK16(0x4800) }, 1);
 */

#ifndef PAWN_H
#define PAWN_H

#include <stdint.h>
#include <stddef.h>

/* Pack a raw posit8/posit16 value into the upper bits of a uint32_t. */
#define PAWN_PACK8(v)    ((uint32_t)(uint8_t)(v)  << 24)
#define PAWN_PACK16(v)   ((uint32_t)(uint16_t)(v) << 16)
#define PAWN_UNPACK8(w)  ((uint8_t) ((w) >> 24))
#define PAWN_UNPACK16(w) ((uint16_t)((w) >> 16))

/* ---- Physical addresses ---- */
#define PAWN_BASE_LITE   0x43C00000UL
#define PAWN_BASE_BURST  0x80000000UL  /* GP1 bit 20 = 0: DBRAM burst           */
#define PAWN_BASE_IBURST 0x80100000UL  /* GP1 bit 20 = 1: IBRAM burst (32-bit)  */
#define PAWN_MAP_SIZE    0x10000UL

/* ---- AXI-Lite register offsets ---- */
#define PAWN_REG_CTRL          0x00  /* [0]=START, [1]=RESET (self-clearing)       */
#define PAWN_REG_STATUS        0x04  /* [0]=DONE,  [1]=RUNNING (read-only)          */
#define PAWN_REG_IBRAM_ADDR    0x08  /* instruction BRAM word index                 */
#define PAWN_REG_IBRAM_DATA_LO 0x0C  /* instr [31:0]                                */
#define PAWN_REG_IBRAM_DATA_HI 0x10  /* instr [63:32]; write triggers BRAM WE       */
#define PAWN_REG_DBRAM_ADDR    0x14  /* data BRAM word index                        */
#define PAWN_REG_DBRAM_DATA    0x18  /* DBRAM word (high DATA_WIDTH bits); rw -> +1 */
#define PAWN_REG_DBRAM_DATA_HI 0x1C  /* DBRAM high word (64-bit only); write -> +1  */

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

/* [63:60] opcode  [59:40] addr_a  [39:20] addr_b  [19:0] addr_result */
#define PAWN_INSTR(op, a, b, r) \
    ( ((uint64_t)(op) << 60) | ((uint64_t)(a) << 40) | \
      ((uint64_t)(b)  << 20) | ((uint64_t)(r)      ) )

/* ---- Device handle ---- */
typedef struct {
    volatile uint32_t *lite;
    volatile uint32_t *burst;   /* DBRAM burst (GP1 bit20=0) */
    volatile uint32_t *iburst;  /* IBRAM burst (GP1 bit20=1) */
    int                devmem_fd;
} pawn_dev_t;

int  pawn_open (pawn_dev_t *dev);
void pawn_close(pawn_dev_t *dev);
void pawn_reset(pawn_dev_t *dev);

/* Load 'count' instructions into IBRAM via AXI-Lite PIO (last must be HALT). */
int pawn_load_program(pawn_dev_t *dev, const uint64_t *instrs, size_t count);

/* Load 'count' instructions into IBRAM via AXI4 burst (faster for large programs).
 * Uses the 32-bit IBRAM burst slave at PAWN_BASE_IBURST: two 32-bit beats per
 * 64-bit instruction word (lo then hi).  Accelerator must not be running. */
int pawn_load_program_burst(pawn_dev_t *dev, const uint64_t *instrs, size_t count);

/* Bulk DBRAM via burst slave. Use write32/read32 for DATA_WIDTH 8/16/32. */
void pawn_dbram_write32(pawn_dev_t *dev, uint32_t base, const uint32_t *data, size_t count);
void pawn_dbram_read32 (pawn_dev_t *dev, uint32_t base,       uint32_t *data, size_t count);
void pawn_dbram_write64(pawn_dev_t *dev, uint32_t base, const uint64_t *data, size_t count);
void pawn_dbram_read64 (pawn_dev_t *dev, uint32_t base,       uint64_t *data, size_t count);

/* Single-word DBRAM via AXI-Lite PIO (debug / sparse access). */
void     pawn_dbram_poke32(pawn_dev_t *dev, uint32_t idx, uint32_t val);
uint32_t pawn_dbram_peek32(pawn_dev_t *dev, uint32_t idx);
void     pawn_dbram_poke64(pawn_dev_t *dev, uint32_t idx, uint64_t val);
uint64_t pawn_dbram_peek64(pawn_dev_t *dev, uint32_t idx);

void      pawn_start(pawn_dev_t *dev);
int       pawn_done (pawn_dev_t *dev);
uint32_t  pawn_status(pawn_dev_t *dev);
/* Starts, blocks until DONE, returns elapsed ns. -1 on timeout (0 = infinite). */
long long pawn_run_blocking(pawn_dev_t *dev, unsigned timeout_ms);

#endif /* PAWN_H */
