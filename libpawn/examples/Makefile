CXX = g++
CXXFLAGS = -std=c++17 -O3 -flto -march=native -mtune=native -funroll-loops -fomit-frame-pointer -pipe
INCLUDE = -I../include

LIBS = ../build/libpawn_static.a -lpthread -lstdc++ -lm

SOURCES = $(wildcard *.cpp)
ELFS = $(SOURCES:.cpp=.elf)

all: $(ELFS)

%.elf: %.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDE) -o $@ $< $(LIBS)

clean:
	rm -f *.elf

.PHONY: all clean