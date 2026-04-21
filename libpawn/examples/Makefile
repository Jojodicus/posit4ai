CXX = g++
CXXFLAGS = -std=c++17 -O2 -lto -I../include -L../build -Wl,-rpath,../build

all: basic_usage.elf

%.elf: %.cpp
	$(CXX) $(CXXFLAGS) -o $@ $< -lpawn

clean:
	rm -f *.elf

.PHONY: all clean
