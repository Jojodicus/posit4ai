ROOT := ..
PAWN_SW := $(ROOT)/PAWN/sw
EXAMPLES_DIR := $(PAWN_SW)/examples
UNIVERSAL_INC := $(ROOT)/spike-xposit/universal/include
UNIVERSAL_INC_SW := $(ROOT)/spike-xposit/universal/include/sw

AR := ar
RANLIB := ranlib
CC := gcc
CXX := g++

CFLAGS := -O2 -Wall -Wextra -std=c11
CXXFLAGS := -O2 -Wall -Wextra -std=c++20 -fno-strict-aliasing
CPPFLAGS := -I$(PAWN_SW) -I$(UNIVERSAL_INC) -I$(UNIVERSAL_INC_SW)

EMU_SRC := pawn_emulsion.cpp
EMU_OBJ8 := pawn_emulsion8.o
EMU_OBJ16 := pawn_emulsion16.o
EMU_OBJ32 := pawn_emulsion32.o

LIB8 := libemulsion8.a
LIB16 := libemulsion16.a
LIB32 := libemulsion32.a

EXAMPLE_NAMES := hello_posit hello_posit2 benchmark long_run_status bench_gemm bench_conv bench_per_op

EMU8_ELFS := $(addsuffix .emu8.elf,$(EXAMPLE_NAMES))
EMU16_ELFS := $(addsuffix .emu16.elf,$(EXAMPLE_NAMES))
EMU32_ELFS := $(addsuffix .emu32.elf,$(EXAMPLE_NAMES))

.PHONY: all libs emu8 emu16 emu32 clean

all: libs emu8 emu16 emu32

libs: $(LIB8) $(LIB16) $(LIB32)

$(EMU_OBJ8): $(EMU_SRC) $(PAWN_SW)/pawn.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -DEMULSION_POSIT_BITS=8 -c -o $@ $<

$(EMU_OBJ16): $(EMU_SRC) $(PAWN_SW)/pawn.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -DEMULSION_POSIT_BITS=16 -c -o $@ $<

$(EMU_OBJ32): $(EMU_SRC) $(PAWN_SW)/pawn.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -DEMULSION_POSIT_BITS=32 -c -o $@ $<

$(LIB8): $(EMU_OBJ8)
	$(AR) rcs $@ $<
	$(RANLIB) $@

$(LIB16): $(EMU_OBJ16)
	$(AR) rcs $@ $<
	$(RANLIB) $@

$(LIB32): $(EMU_OBJ32)
	$(AR) rcs $@ $<
	$(RANLIB) $@

emu8: $(LIB8) $(EMU8_ELFS)

emu16: $(LIB16) $(EMU16_ELFS)

emu32: $(LIB32) $(EMU32_ELFS)

%.emu8.elf: $(EXAMPLES_DIR)/%.c $(LIB8) $(PAWN_SW)/pawn.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LIB8) -lstdc++ -lm

%.emu16.elf: $(EXAMPLES_DIR)/%.c $(LIB16) $(PAWN_SW)/pawn.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LIB16) -lstdc++ -lm

%.emu32.elf: $(EXAMPLES_DIR)/%.c $(LIB32) $(PAWN_SW)/pawn.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LIB32) -lstdc++ -lm

clean:
	rm -f $(EMU_OBJ8) $(EMU_OBJ16) $(EMU_OBJ32)
	rm -f $(LIB8) $(LIB16) $(LIB32)
	rm -f $(EMU8_ELFS) $(EMU16_ELFS) $(EMU32_ELFS)
