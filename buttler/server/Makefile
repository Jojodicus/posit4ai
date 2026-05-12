# PAWN SmallNet inference server
# Cross-compile for Zedboard (ARMv7 hard-float):
#   make
# Native build (on the board itself):
#   make CROSS=""
# Host-side EMULSION build:
#   make emuserver         # builds all three:
#   make server.emu8       # posit<8,2>
#   make server.emu16      # posit<16,2>
#   make server.emu32      # posit<32,2>

CROSS  ?= arm-linux-gnueabihf-
CC     := $(CROSS)gcc
PAWN   := ../../PAWN/sw
CFLAGS := -O2 -Wall -Wextra -std=c11 -static -I$(PAWN)

EMUL      := ../../EMULSION
EMU_CC    := gcc
EMU_CFLAGS := -O2 -Wall -Wextra -std=c11 -I$(PAWN)

.PHONY: all clean emuserver

all: server emuserver

server: server.c $(PAWN)/pawn.c $(PAWN)/pawn.h
	$(CC) $(CFLAGS) -o server server.c $(PAWN)/pawn.c

server.emu8: server.c $(EMUL)/libemulsion8.a
	$(EMU_CC) $(EMU_CFLAGS) -o $@ server.c $(EMUL)/libemulsion8.a -lstdc++ -lm

server.emu16: server.c $(EMUL)/libemulsion16.a
	$(EMU_CC) $(EMU_CFLAGS) -o $@ server.c $(EMUL)/libemulsion16.a -lstdc++ -lm

server.emu32: server.c $(EMUL)/libemulsion32.a
	$(EMU_CC) $(EMU_CFLAGS) -o $@ server.c $(EMUL)/libemulsion32.a -lstdc++ -lm

emuserver: server.emu8 server.emu16 server.emu32

clean:
	rm -f server server.emu8 server.emu16 server.emu32
