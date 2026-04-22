#include "libpawn.hpp"

p::Target::Target(uint32_t dataWidth, Datatype dataType) : dataWidth(dataWidth), dataType(dataType) {}

p::UniversalTarget::UniversalTarget(uint32_t dataWidth)
    : p::Target(dataWidth, POSIT), quire(nullptr) {}

p::FloatTarget::FloatTarget(uint32_t dataWidth)
    : p::Target(dataWidth, FLOAT), acc(nullptr) {}

p::UniversalTarget::~UniversalTarget() { delete quire; }
p::FloatTarget::~FloatTarget() { delete acc; }