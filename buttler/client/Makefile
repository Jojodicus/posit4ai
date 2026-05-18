UNIVERSAL_INC := ../../spike-xposit/universal/include

CXX      := g++
CXXFLAGS := -O2 -std=c++20 -fno-strict-aliasing -fPIC -shared
CPPFLAGS := -I$(UNIVERSAL_INC) -I$(UNIVERSAL_INC)/sw

.PHONY: all clean

all: posit_convert.so

posit_convert.so: posit_convert.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -o $@ $<

clean:
	rm -f posit_convert.so
