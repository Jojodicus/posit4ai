# PAWN SmallNet inference server
# Cross-compile for Zedboard (ARMv7 hard-float):
#   make
# Native build (on the board itself):
#   make CROSS=""

CROSS  ?= arm-linux-gnueabihf-
CC     := $(CROSS)gcc
PAWN   := ../../PAWN/sw
CFLAGS := -O2 -Wall -Wextra -std=c11 -static -I$(PAWN)

.PHONY: all clean

all: server

server: server.c $(PAWN)/pawn.c $(PAWN)/pawn.h
	$(CC) $(CFLAGS) -o server server.c $(PAWN)/pawn.c

clean:
	rm -f server
