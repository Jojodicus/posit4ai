# PAWN userspace driver + examples
#
# Cross-compilation for Zedboard (ARMv7 hard-float):
#   make
#
# Native build (when already on the board or for testing):
#   make CROSS=""

CROSS ?= arm-linux-gnueabihf-
CC    := $(CROSS)gcc
CXX   := $(CROSS)g++
CFLAGS   := -O2 -Wall -Wextra -std=c11   -static
CXXFLAGS := -O2 -Wall -Wextra -Wno-unused-function -std=c++20 -static

LIBPAWN_DIR   := ../../libpawn
UNIVERSAL_INC := ../../spike-xposit/universal/include/sw

LIBPAWN_SRCS := \
    $(LIBPAWN_DIR)/src/targets/default.cpp \
    $(LIBPAWN_DIR)/src/targets/universal/posit32.cpp \
    $(LIBPAWN_DIR)/src/targets/universal/posit64.cpp \
    $(LIBPAWN_DIR)/src/targets/float/float32.cpp \
    $(LIBPAWN_DIR)/src/targets/float/float64.cpp

LIBPAWN_OBJS := $(patsubst $(LIBPAWN_DIR)/src/%.cpp, libpawn_obj/%.o, $(LIBPAWN_SRCS))

LIBPAWN_INC := -I$(LIBPAWN_DIR)/include -I$(UNIVERSAL_INC)

DRIVER_OBJ   := pawn.o
EXAMPLES_C   := hello_posit.elf hello_posit64.elf benchmark.elf long_run_status.elf
EXAMPLES_CXX := bench_gemm.elf bench_conv.elf
EXAMPLE_BINS := $(addprefix examples/, $(EXAMPLES_C) $(EXAMPLES_CXX))

.PHONY: all clean

all: $(EXAMPLE_BINS)

$(DRIVER_OBJ): pawn.c pawn.h
	$(CC) $(CFLAGS) -c -o $@ $<

examples/%.elf: examples/%.c $(DRIVER_OBJ) pawn.h
	$(CC) $(CFLAGS) -o $@ $< $(DRIVER_OBJ)

libpawn_obj/%.o: $(LIBPAWN_DIR)/src/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(LIBPAWN_INC) -c -o $@ $<

examples/bench_gemm.elf: examples/bench_gemm.cpp examples/bench_common.hpp \
        $(DRIVER_OBJ) $(LIBPAWN_OBJS) pawn.h
	$(CXX) $(CXXFLAGS) $(LIBPAWN_INC) -o $@ $< $(DRIVER_OBJ) $(LIBPAWN_OBJS)

examples/bench_conv.elf: examples/bench_conv.cpp examples/bench_common.hpp \
        $(DRIVER_OBJ) $(LIBPAWN_OBJS) pawn.h
	$(CXX) $(CXXFLAGS) $(LIBPAWN_INC) -o $@ $< $(DRIVER_OBJ) $(LIBPAWN_OBJS)

clean:
	rm -f $(DRIVER_OBJ) $(EXAMPLE_BINS)
	rm -rf libpawn_obj/
