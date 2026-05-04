#include "../pawn.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/*
 * Long-running status probe.
 *
 * NOTE: INSTR_DEPTH defaults to 2^15, so max program length is 32768 words.
 * This test uses 32767 MOV ops + 1 HALT = 32768 total.
 */

#define MAX_INSTR_WORDS 32768u
#define MOV_COUNT       (MAX_INSTR_WORDS - 1u)

int main(void)
{
    pawn_dev_t dev;
    uint64_t *prog;
    uint32_t src = 0x40000000u; /* posit32 1.0 */
    uint32_t dst = 0u;
    unsigned saw_running = 0;

    printf("long_run_status: opening pawn\n");
    if (pawn_open(&dev) != 0)
        return 1;

    pawn_reset(&dev);
    printf("status after reset: 0x%08X\n", pawn_status(&dev));

    pawn_dbram_write32(&dev, 0, &src, 1);

    prog = (uint64_t *)malloc(sizeof(uint64_t) * MAX_INSTR_WORDS);
    if (!prog) {
        fprintf(stderr, "malloc failed\n");
        pawn_close(&dev);
        return 1;
    }

    for (uint32_t i = 0; i < MOV_COUNT; i++) {
        uint32_t dst_addr = 1u + (i % 1024u);
        prog[i] = PAWN_INSTR(PAWN_OP_MOV, 0u, 0u, dst_addr);
    }
    prog[MOV_COUNT] = PAWN_INSTR(PAWN_OP_HALT, 0u, 0u, 0u);

    if (pawn_load_program(&dev, prog, MAX_INSTR_WORDS) != 0) {
        fprintf(stderr, "pawn_load_program failed\n");
        free(prog);
        pawn_close(&dev);
        return 1;
    }
    free(prog);

    pawn_start(&dev);
    for (unsigned i = 0; i < 2000000u; i++) {
        uint32_t st = pawn_status(&dev);
        if (st & PAWN_STATUS_RUNNING)
            saw_running = 1;
        if ((st & PAWN_STATUS_DONE) && !(st & PAWN_STATUS_RUNNING)) {
            printf("done at poll %u, status=0x%08X\n", i, st);
            break;
        }
        if (i == 1999999u)
            printf("timeout-like poll end, status=0x%08X\n", st);
    }

    pawn_dbram_read32(&dev, 1, &dst, 1);
    printf("saw_running=%u\n", saw_running);
    printf("DBRAM[0]=0x%08X DBRAM[1]=0x%08X\n", src, dst);

    pawn_close(&dev);
    return 0;
}
