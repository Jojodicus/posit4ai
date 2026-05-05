#include <iostream>
#include "libpawn.hpp"

int main() {
    p::Posit32Target target;

    p::Number a = target.toNumber(2.0f);
    p::Number b = target.toNumber(3.0f);

    p::Number sum = target.add(a, b);
    p::Number prod = target.mul(a, b);

    std::cout << "2.0 + 3.0 = " << target.toFloat(sum) << "\n";
    std::cout << "2.0 * 3.0 = " << target.toFloat(prod) << "\n";

    return 0;
}