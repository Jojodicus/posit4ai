# PAWN userspace driver + examples
#
# Cross-compilation for Zedboard (ARMv7 hard-float):
#   make CROSS=arm-linux-gnueabihf-
#
# Native build (when already on the board):
#   make

CROSS ?=
CC    := $(CROSS)gcc
CFLAGS := -O2 -Wall -Wextra -std=c11

DRIVER_OBJ   := pawn.o
EXAMPLES     := hello_posit.elf benchmark.elf
EXAMPLE_BINS := $(addprefix examples/, $(EXAMPLES))

.PHONY: all clean

all: $(EXAMPLE_BINS)

$(DRIVER_OBJ): pawn.c pawn.h
	$(CC) $(CFLAGS) -c -o $@ $<

examples/%.elf: examples/%.c $(DRIVER_OBJ) pawn.h
	$(CC) $(CFLAGS) -o $@ $< $(DRIVER_OBJ)

clean:
	rm -f $(DRIVER_OBJ) $(EXAMPLE_BINS)
