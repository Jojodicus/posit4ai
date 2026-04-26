#include "pawn.h"

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

/* Maximum word indices supported by 20-bit address fields */
#define IBRAM_DEPTH (1u << 15)
#define DBRAM_DEPTH (1u << 15)

static inline uint32_t reg_read(volatile uint32_t *base, unsigned offset)
{
    return *(volatile uint32_t *)((volatile char *)base + offset);
}

static inline void reg_write(volatile uint32_t *base, unsigned offset,
                              uint32_t val)
{
    *(volatile uint32_t *)((volatile char *)base + offset) = val;
}

int pawn_open(pawn_dev_t *dev)
{
    dev->devmem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (dev->devmem_fd < 0) {
        perror("pawn_open: open /dev/mem");
        return -1;
    }

    dev->lite = (volatile uint32_t *)mmap(NULL, PAWN_MAP_SIZE,
                                          PROT_READ | PROT_WRITE,
                                          MAP_SHARED,
                                          dev->devmem_fd, PAWN_BASE_LITE);
    if (dev->lite == MAP_FAILED) {
        perror("pawn_open: mmap AXI-Lite");
        close(dev->devmem_fd);
        return -1;
    }

    dev->burst = (volatile uint32_t *)mmap(NULL, PAWN_MAP_SIZE,
                                           PROT_READ | PROT_WRITE,
                                           MAP_SHARED,
                                           dev->devmem_fd, PAWN_BASE_BURST);
    if (dev->burst == MAP_FAILED) {
        perror("pawn_open: mmap AXI burst");
        munmap((void *)dev->lite, PAWN_MAP_SIZE);
        close(dev->devmem_fd);
        return -1;
    }

    return 0;
}

void pawn_close(pawn_dev_t *dev)
{
    if (dev->burst && dev->burst != MAP_FAILED)
        munmap((void *)dev->burst, PAWN_MAP_SIZE);
    if (dev->lite && dev->lite != MAP_FAILED)
        munmap((void *)dev->lite, PAWN_MAP_SIZE);
    if (dev->devmem_fd >= 0)
        close(dev->devmem_fd);
    memset(dev, 0, sizeof(*dev));
    dev->devmem_fd = -1;
}

void pawn_reset(pawn_dev_t *dev)
{
    reg_write(dev->lite, PAWN_REG_CTRL, 1u << 1);  /* RESET bit */
}

int pawn_load_program(pawn_dev_t *dev, const uint64_t *instrs, size_t count)
{
    if (count > IBRAM_DEPTH) {
        fprintf(stderr, "pawn_load_program: count %zu > IBRAM_DEPTH %u\n",
                count, IBRAM_DEPTH);
        return -1;
    }

    reg_write(dev->lite, PAWN_REG_IBRAM_ADDR, 0);

    for (size_t i = 0; i < count; i++) {
        uint32_t lo = (uint32_t)(instrs[i] & 0xFFFFFFFFu);
        uint32_t hi = (uint32_t)(instrs[i] >> 32);
        reg_write(dev->lite, PAWN_REG_IBRAM_DATA_LO, lo);
        /* writing HI triggers the BRAM write and auto-increments IBRAM_ADDR */
        reg_write(dev->lite, PAWN_REG_IBRAM_DATA_HI, hi);
    }

    return 0;
}

void pawn_dbram_write(pawn_dev_t *dev, uint32_t base, const uint32_t *data,
                      size_t count)
{
    /* Burst slave: address in the mmap'd window corresponds directly to
     * DBRAM index.  One 32-bit word per DBRAM entry for DATA_WIDTH=32. */
    volatile uint32_t *dst = dev->burst + base;
    for (size_t i = 0; i < count; i++)
        dst[i] = data[i];
}

void pawn_dbram_read(pawn_dev_t *dev, uint32_t base, uint32_t *data,
                     size_t count)
{
    volatile uint32_t *src = dev->burst + base;
    for (size_t i = 0; i < count; i++)
        data[i] = src[i];
}

void pawn_start(pawn_dev_t *dev)
{
    reg_write(dev->lite, PAWN_REG_CTRL, 1u << 0);  /* START bit */
}

int pawn_done(pawn_dev_t *dev)
{
    return (reg_read(dev->lite, PAWN_REG_STATUS) & PAWN_STATUS_DONE) != 0;
}

uint32_t pawn_status(pawn_dev_t *dev)
{
    return reg_read(dev->lite, PAWN_REG_STATUS);
}

long long pawn_run_blocking(pawn_dev_t *dev, unsigned timeout_ms)
{
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    pawn_start(dev);

    while (!pawn_done(dev)) {
        if (timeout_ms) {
            clock_gettime(CLOCK_MONOTONIC, &t1);
            long long elapsed_ms =
                (t1.tv_sec  - t0.tv_sec)  * 1000LL +
                (t1.tv_nsec - t0.tv_nsec) / 1000000LL;
            if (elapsed_ms > (long long)timeout_ms) {
                fprintf(stderr, "pawn_run_blocking: timeout after %u ms\n",
                        timeout_ms);
                return -1;
            }
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    return (t1.tv_sec  - t0.tv_sec)  * 1000000000LL +
           (t1.tv_nsec - t0.tv_nsec);
}
