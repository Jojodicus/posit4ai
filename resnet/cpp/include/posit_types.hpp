#pragma once

#include <universal/posit/posit>

using namespace sw::unum;

template<size_t N, size_t E>
struct PType {
    using Optimizer = posit<N, E>;
    using Forward   = posit<N, E>;
    using Backward  = posit<N, E>;
    using Gradient  = posit<N, E>;
    using Loss      = posit<N, E>;
};
