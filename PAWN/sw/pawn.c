#define _POSIX_C_SOURCE 199309L
#include "pawn.h"

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#define IBRAM_DEPTH (1u << 15)

static inline int axi_full() {
    char *env = getenv("AXI_FULL");
    return env != NULL && *env == '1';
}

static inline uint32_t reg_read(volatile uint32_t *base, unsigned off)
{
    return *(volatile uint32_t *)((volatile char *)base + off);
}

static inline void reg_write(volatile uint32_t *base, unsigned off, uint32_t v)
{
    *(volatile uint32_t *)((volatile char *)base + off) = v;
}

/*
 * pawn_mmio_fence: full memory barrier; orders all preceding MMIO accesses
 * before any subsequent ones.
 */
static inline void pawn_mmio_fence(void)
{
    __sync_synchronize();
}

/*
 * pawn_burst_fence32: drain the AXI write buffer for the GP1 burst port.
 * Issues a barrier, then a read-back from a known readable address on the
 * same GP1 port (DBRAM word 0), then another barrier.  The read-back forces
 * all preceding burst writes to complete before the read response returns.
 * Use for DBRAM burst writes (dev->burst).
 */
static inline void pawn_burst_fence32(pawn_dev_t *dev)
{
    volatile uint32_t sink;
    pawn_mmio_fence();
    sink = dev->burst[0];
    (void)sink;
    pawn_mmio_fence();
}

/*
 * pawn_iburst_fence32: drain the AXI write buffer for the GP1 IBRAM burst port.
 * GP1 iburst reads return SLVERR (SIGBUS under Linux), so we cannot fence via
 * a read-back from dev->iburst.  Instead: drain GP1 with the DBRAM read-back
 * (same physical AXI master port -- all prior GP1 writes complete before GP1
 * reads are issued for device-mapped memory with a preceding DMB), then
 * read STATUS from the AXI-Lite port (GP0) to ensure the GP0 path that carries
 * pawn_start is ordered after all preceding memory operations.
 */
static inline void pawn_iburst_fence32(pawn_dev_t *dev)
{
    volatile uint32_t sink;
    /* Drain the GP1 write buffer: DMB + GP1 readback. */
    pawn_mmio_fence();
    sink = dev->burst[0];
    (void)sink;
    /* Drain GP0 path: STATUS read ensures pawn_start cannot overtake iburst. */
    pawn_mmio_fence();
    sink = reg_read(dev->lite, PAWN_REG_STATUS);
    (void)sink;
    pawn_mmio_fence();
}

/* ---- Lifecycle ---- */

int pawn_open(pawn_dev_t *dev)
{
    memset(dev, 0, sizeof(*dev));
    dev->devmem_fd = -1;

    dev->devmem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (dev->devmem_fd < 0) {
        perror("pawn_open: /dev/mem");
        return -1;
    }
    dev->lite = (volatile uint32_t *)mmap(NULL, PAWN_MAP_SIZE,
                                          PROT_READ | PROT_WRITE, MAP_SHARED,
                                          dev->devmem_fd, PAWN_BASE_LITE);
    if (dev->lite == MAP_FAILED) {
        perror("pawn_open: mmap AXI-Lite");
        close(dev->devmem_fd);
        return -1;
    }
    dev->burst = (volatile uint32_t *)mmap(NULL, PAWN_MAP_SIZE,
                                           PROT_READ | PROT_WRITE, MAP_SHARED,
                                           dev->devmem_fd, PAWN_BASE_BURST);
    if (dev->burst == MAP_FAILED) {
        perror("pawn_open: mmap burst");
        munmap((void *)dev->lite, PAWN_MAP_SIZE);
        close(dev->devmem_fd);
        return -1;
    }
    dev->iburst = (volatile uint32_t *)mmap(NULL, PAWN_MAP_SIZE,
                                            PROT_READ | PROT_WRITE, MAP_SHARED,
                                            dev->devmem_fd, PAWN_BASE_IBURST);
    if (dev->iburst == MAP_FAILED) {
        perror("pawn_open: mmap iburst");
        munmap((void *)dev->burst, PAWN_MAP_SIZE);
        munmap((void *)dev->lite,  PAWN_MAP_SIZE);
        close(dev->devmem_fd);
        return -1;
    }
    return 0;
}

void pawn_close(pawn_dev_t *dev)
{
    if (dev->iburst && dev->iburst != MAP_FAILED)
        munmap((void *)dev->iburst, PAWN_MAP_SIZE);
    if (dev->burst  && dev->burst  != MAP_FAILED)
        munmap((void *)dev->burst,  PAWN_MAP_SIZE);
    if (dev->lite   && dev->lite   != MAP_FAILED)
        munmap((void *)dev->lite,   PAWN_MAP_SIZE);
    if (dev->devmem_fd >= 0)
        close(dev->devmem_fd);
    memset(dev, 0, sizeof(*dev));
    dev->devmem_fd = -1;
}

void pawn_reset(pawn_dev_t *dev)
{
    const struct timespec us1 = { .tv_sec = 0, .tv_nsec = 1000 };

    reg_write(dev->lite, PAWN_REG_CTRL, 1u << 1);

    /*
     * RESET is pulsed in clk_bram then synchronized into clk_core.
     * Poll until status clears (not running, not done) before issuing the
     * next START so stale DONE is not accepted as the new run's completion.
     */
    for (unsigned i = 0; i < 10000u; i++) {
        if ((reg_read(dev->lite, PAWN_REG_STATUS) & (PAWN_STATUS_DONE | PAWN_STATUS_RUNNING)) == 0)
            break;
        nanosleep(&us1, NULL);
    }
}

/* ---- Program load ---- */

static int load_program_lite(pawn_dev_t *dev, const uint64_t *instrs, size_t count) {
    /*
     * FIFO-style IBRAM load: set address once, then stream lo+hi pairs.
     * IBRAM_DATA_HI write triggers BRAM write and auto-increments IBRAM_ADDR.
     */
    reg_write(dev->lite, PAWN_REG_IBRAM_ADDR, 0);
    for (size_t i = 0; i < count; i++) {
        reg_write(dev->lite, PAWN_REG_IBRAM_DATA_LO, (uint32_t)(instrs[i]));
        reg_write(dev->lite, PAWN_REG_IBRAM_DATA_HI, (uint32_t)(instrs[i] >> 32));
    }
    /* Fence: read STATUS to drain posted AXI-Lite writes */
    (void)reg_read(dev->lite, PAWN_REG_STATUS);
    return 0;
}

static int load_program_burst(pawn_dev_t *dev, const uint64_t *instrs, size_t count)
{
    /*
     * IBRAM burst slave: 32-bit AXI4 bus, byte address = word_index * 8.
     * Two 32-bit writes per 64-bit instruction: iburst[i*2]=lo, iburst[i*2+1]=hi.
     * The hardware assembles {hi, lo} and commits to IBRAM on the hi beat.
     */
    volatile uint32_t *dst = dev->iburst;
    for (size_t i = 0; i < count; i++) {
        dst[i * 2]     = (uint32_t)(instrs[i]);
        dst[i * 2 + 1] = (uint32_t)(instrs[i] >> 32);
    }
    if (count)
        pawn_iburst_fence32(dev);
    return 0;
}

int pawn_load_program(pawn_dev_t *dev, const uint64_t *instrs, size_t count)
{
    if (axi_full()) {
        return load_program_burst(dev, instrs, count);
    } else {
        return load_program_lite(dev, instrs, count);
    }
}

/* ---- DBRAM read/write ---- */

void pawn_dbram_write32(pawn_dev_t *dev, uint32_t base, const uint32_t *data,
                         size_t count)
{
    if (axi_full()) {
        volatile uint32_t *dst = dev->burst + base;
        for (size_t i = 0; i < count; i++)
            dst[i] = data[i];
        if (count)
            pawn_burst_fence32(dev);
    } else {
        /* FIFO-style: set address once, write HI=0 once, then stream DATA writes */
        reg_write(dev->lite, PAWN_REG_DBRAM_ADDR, base);
        reg_write(dev->lite, PAWN_REG_DBRAM_DATA_HI, 0);  /* clear stale HI */
        for (size_t i = 0; i < count; i++) {
            reg_write(dev->lite, PAWN_REG_DBRAM_DATA, data[i]);
        }
        /* Fence: read STATUS to drain posted AXI-Lite writes */
        (void)reg_read(dev->lite, PAWN_REG_STATUS);
    }
}

void pawn_dbram_write64(pawn_dev_t *dev, uint32_t base, const uint64_t *data,
                         size_t count)
{
    if (axi_full()) {
        /*
         * DATA_WIDTH=64: BRAM[i] spans [i*8 .. i*8+7].
         * Two 32-bit GP1 writes per BRAM word: burst[base*2 + i*2]=lo, +1=hi.
         */
        volatile uint32_t *dst = dev->burst + base * 2;
        for (size_t i = 0; i < count; i++) {
            dst[i * 2]     = (uint32_t)(data[i]);
            dst[i * 2 + 1] = (uint32_t)(data[i] >> 32);
        }
        if (count)
            pawn_burst_fence32(dev);
    } else {
        /* FIFO-style: set address once, then stream LO+HI pairs (HI triggers + inc) */
        reg_write(dev->lite, PAWN_REG_DBRAM_ADDR, base);
        for (size_t i = 0; i < count; i++) {
            reg_write(dev->lite, PAWN_REG_DBRAM_DATA,    (uint32_t)(data[i]));
            reg_write(dev->lite, PAWN_REG_DBRAM_DATA_HI, (uint32_t)(data[i] >> 32));
        }
        /* Fence: read STATUS to drain posted AXI-Lite writes */
        (void)reg_read(dev->lite, PAWN_REG_STATUS);
    }
}

void pawn_dbram_read32(pawn_dev_t *dev, uint32_t base, uint32_t *data,
                       size_t count)
{
    if (axi_full()) {
        pawn_mmio_fence();
        volatile uint32_t *src = dev->burst + base;
        for (size_t i = 0; i < count; i++)
            data[i] = src[i];
    } else {
        /* FIFO-style: set address once, then stream DATA reads (auto-inc) */
        pawn_mmio_fence();
        reg_write(dev->lite, PAWN_REG_DBRAM_ADDR, base);
        for (size_t i = 0; i < count; i++) {
            data[i] = reg_read(dev->lite, PAWN_REG_DBRAM_DATA);
        }
    }
}

void pawn_dbram_read64(pawn_dev_t *dev, uint32_t base, uint64_t *data,
                       size_t count)
{
    if (axi_full()) {
        pawn_mmio_fence();
        volatile uint32_t *src = dev->burst + base * 2;
        for (size_t i = 0; i < count; i++)
            data[i] = (uint64_t)src[i * 2] | ((uint64_t)src[i * 2 + 1] << 32);
    } else {
        /* FIFO-style: set address once, then stream LO+HI reads (HI inc) */
        pawn_mmio_fence();
        reg_write(dev->lite, PAWN_REG_DBRAM_ADDR, base);
        for (size_t i = 0; i < count; i++) {
            uint32_t lo = reg_read(dev->lite, PAWN_REG_DBRAM_DATA);
            uint32_t hi = reg_read(dev->lite, PAWN_REG_DBRAM_DATA_HI);
            data[i] = (uint64_t)lo | ((uint64_t)hi << 32);
        }
    }
}

/* ---- DBRAM single-word PIO via AXI-Lite ---- */
/* For 32-bit: write HI=0 then DATA (trigger). For 64-bit: LO then HI (HI triggers). */

void pawn_dbram_poke32(pawn_dev_t *dev, uint32_t idx, uint32_t val)
{
    reg_write(dev->lite, PAWN_REG_DBRAM_ADDR, idx);
    reg_write(dev->lite, PAWN_REG_DBRAM_DATA_HI, 0);   /* clear stale HI */
    reg_write(dev->lite, PAWN_REG_DBRAM_DATA, val);    /* trigger for 32-bit */
}

uint32_t pawn_dbram_peek32(pawn_dev_t *dev, uint32_t idx)
{
    reg_write(dev->lite, PAWN_REG_DBRAM_ADDR, idx);
    return reg_read(dev->lite, PAWN_REG_DBRAM_DATA);  /* auto-inc for 32-bit */
}

void pawn_dbram_poke64(pawn_dev_t *dev, uint32_t idx, uint64_t val)
{
    reg_write(dev->lite, PAWN_REG_DBRAM_ADDR, idx);
    reg_write(dev->lite, PAWN_REG_DBRAM_DATA,    (uint32_t)(val));
    reg_write(dev->lite, PAWN_REG_DBRAM_DATA_HI, (uint32_t)(val >> 32)); /* trigger */
}

uint64_t pawn_dbram_peek64(pawn_dev_t *dev, uint32_t idx)
{
    reg_write(dev->lite, PAWN_REG_DBRAM_ADDR, idx);
    uint32_t lo = reg_read(dev->lite, PAWN_REG_DBRAM_DATA);
    uint32_t hi = reg_read(dev->lite, PAWN_REG_DBRAM_DATA_HI); /* auto-inc */
    return (uint64_t)lo | ((uint64_t)hi << 32);
}

/* ---- Execution ---- */

void pawn_start(pawn_dev_t *dev)
{
    pawn_mmio_fence();
    reg_write(dev->lite, PAWN_REG_CTRL, 1u << 0);
    /* Fence: ensure START reaches the device before we poll DONE */
    (void)reg_read(dev->lite, PAWN_REG_STATUS);
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
    uint32_t st0 = pawn_status(dev);
    int done_was_high = (st0 & PAWN_STATUS_DONE) != 0;
    int observed_new_run = !done_was_high;

    clock_gettime(CLOCK_MONOTONIC, &t0);

    /*
     * DONE can be high before START (e.g. previous run ended in HALT_S).
     * If so, do not accept DONE until we first observe DONE go low or RUNNING high.
     */
    pawn_start(dev);

    while (1) {
        uint32_t st = pawn_status(dev);
        if ((st & PAWN_STATUS_RUNNING) || !(st & PAWN_STATUS_DONE))
            observed_new_run = 1;

        if (observed_new_run && (st & PAWN_STATUS_DONE) && !(st & PAWN_STATUS_RUNNING))
            break;

        if (timeout_ms) {
            clock_gettime(CLOCK_MONOTONIC, &t1);
            long long ms = (t1.tv_sec  - t0.tv_sec)  * 1000LL
                         + (t1.tv_nsec - t0.tv_nsec) / 1000000LL;
            if (ms > (long long)timeout_ms) {
                fprintf(stderr, "pawn_run_blocking: timeout (%u ms)\n", timeout_ms);
                return -1;
            }
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    return (t1.tv_sec  - t0.tv_sec)  * 1000000000LL
         + (t1.tv_nsec - t0.tv_nsec);
}
