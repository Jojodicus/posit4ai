#include <iostream>
#include "libpawn.hpp"

int main() {
    std::cout << "Hello from libpawn!\n";

    p::UniversalTarget target(32);
    std::cout << "Created UniversalTarget with dataWidth=" << target.dataWidth << "\n";

    p::Number n = target.toNumber(3.14f);
    std::cout << "Converted 3.14f to Number\n";

    float f = target.toFloat(n);
    std::cout << "Converted back to float: " << f << "\n";

    return 0;
}