#pragma once

#include <cstdint>
#include <cmath>
#include <limits>

#include <universal/number/posit/posit.hpp>
#include <universal/number/posit/fdp.hpp>
#include <universal/number/quire/quire.hpp>

namespace p {

template<unsigned nbits, unsigned es>
using UniversalPosit = sw::universal::posit<nbits, es>;

template<unsigned nbits, unsigned es>
using UniversalQuire = sw::universal::quire<UniversalPosit<nbits, es>>;

using Posit8 = UniversalPosit<8, 2>;
using Posit16 = UniversalPosit<16, 2>;
using Posit32 = UniversalPosit<32, 2>;
using Posit64 = UniversalPosit<64, 2>;

using Quire8 = sw::universal::quire<Posit8>;
using Quire16 = sw::universal::quire<Posit16>;
using Quire32 = sw::universal::quire<Posit32>;
using Quire64 = sw::universal::quire<Posit64>;

template<typename P>
static inline uint64_t posit_to_bits(const P& p) {
    return static_cast<uint64_t>(p.bits().to_ull());
}

template<typename P>
static inline P bits_to_posit(uint64_t bits) {
    P p;
    p.setbits(bits);
    return p;
}

} // namespace p