# PAWN userspace driver + examples
#
# Cross-compilation (Zedboard ARMv7 hard-float):
#   make CROSS=arm-linux-gnueabihf-
#
# Native build (when already on the board):
#   make
#
# CLOCK_FREQ_MHZ must match the frequency used in ./impl.sh:
#   make CROSS=arm-linux-gnueabihf- CLOCK_FREQ_MHZ=30

CROSS        ?=
CC           := $(CROSS)gcc
CFLAGS       := -O2 -Wall -Wextra -std=c11
CLOCK_FREQ_MHZ ?= 30
CFLAGS       += -DCLOCK_FREQ_MHZ=$(CLOCK_FREQ_MHZ)

DRIVER_SRC   := pawn.c
DRIVER_OBJ   := pawn.o

EXAMPLES     := hello_posit benchmark
EXAMPLE_BINS := $(addprefix examples/, $(EXAMPLES))

.PHONY: all clean

all: $(EXAMPLE_BINS)

$(DRIVER_OBJ): $(DRIVER_SRC) pawn.h
	$(CC) $(CFLAGS) -c -o $@ $<

examples/%: examples/%.c $(DRIVER_OBJ) pawn.h
	$(CC) $(CFLAGS) -o $@ $< $(DRIVER_OBJ)

clean:
	rm -f $(DRIVER_OBJ) $(EXAMPLE_BINS)
