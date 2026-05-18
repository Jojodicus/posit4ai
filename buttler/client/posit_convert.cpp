#include <sw/universal/number/posit/posit.hpp>
#include <cstddef>
#include <cstdint>

using Posit32 = sw::universal::posit<32, 2>;

extern "C" {

void float_to_posit32_array(const float* in, uint32_t* out, size_t n) {
    for (size_t i = 0; i < n; ++i) {
        Posit32 p(in[i]);
        out[i] = static_cast<uint32_t>(p.bits().to_ull());
    }
}

} // extern "C"
