#include <iostream>
#include <chrono>
#include "libpawn.hpp"

#define N 1000

int main(int argc, char** argv) {
    p::Posit32Target target;

    p::Number one = target.toNumber(1.0f);

    int iterations = N;
    if (argc > 1) {
        iterations = atoi(argv[1]);
    }

    // warm up
    for (int i = 0; i < 10; ++i) {
        target.add(one, one);
    }

    auto start = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < iterations; ++i) {
        target.add(one, one);
    }
    auto end = std::chrono::high_resolution_clock::now();

    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
    std::cout << iterations << " iterations" << std::endl;
    std::cout << duration.count() << " us" << std::endl;
}
