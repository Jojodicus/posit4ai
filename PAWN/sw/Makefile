# PAWN userspace driver + examples
#
# Cross-compilation for Zedboard (ARMv7 hard-float):
#   make
#
# Native build (when already on the board or for testing):
#   make CROSS=""

CROSS ?= arm-linux-gnueabihf-
CC    := $(CROSS)gcc
CFLAGS := -O2 -Wall -Wextra -std=c11 -static

DRIVER_OBJ   := pawn.o
EXAMPLES     := hello_posit.elf hello_posit2.elf hello_posit64.elf benchmark.elf long_run_status.elf \
                bench_gemm.elf bench_conv.elf \
                bench_per_op.elf bench_per_op64.elf bench_gemm64.elf bench_conv64.elf
EXAMPLE_BINS := $(addprefix examples/, $(EXAMPLES))

.PHONY: all clean

all: $(EXAMPLE_BINS)

$(DRIVER_OBJ): pawn.c pawn.h
	$(CC) $(CFLAGS) -c -o $@ $<

examples/%.elf: examples/%.c $(DRIVER_OBJ) pawn.h
	$(CC) $(CFLAGS) -o $@ $< $(DRIVER_OBJ)

clean:
	rm -f $(DRIVER_OBJ) $(EXAMPLE_BINS)
