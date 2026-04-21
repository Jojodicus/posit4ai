#include "libpawn.hpp"
#include "universal/number/posit/posit.hpp"

using posit64 = sw::universal::posit<64, 2>;
using posit32 = sw::universal::posit<32, 2>;
using posit16 = sw::universal::posit<16, 2>;
using posit8 = sw::universal::posit<8, 2>;
using quire64 = sw::universal::quire<posit64>;
using quire32 = sw::universal::quire<posit32>;
using quire16 = sw::universal::quire<posit16>;
using quire8 = sw::universal::quire<posit8>;

p::UniversalTarget::UniversalTarget(int dataWidth, Datatype dataType) : Target(dataWidth, dataType)
{
    if (dataType == POSIT)
    {
        switch (dataWidth)
        {
        case 8:
            quire = new quire8{};
            break;
        case 16:
            quire = new quire16{};
            break;
        case 32:
            quire = new quire32{};
            break;
        case 64:
            quire = new quire64{};
            break;
        default:
            throw "Invalid data width for universal posits";
        }
    }
    else // FLOAT
    {
        switch (dataWidth)
        {
        case 32:
            quire = new float;
            break;
        case 64:
            quire = new double;
            break;
        default:
            throw "Invalid data width for universal floats";
        }
    }
}

void p::UniversalTarget::qaClear()
{
    if (dataType == POSIT)
    {
        switch (dataWidth)
        {
        case 8:
            reinterpret_cast<quire8*>(quire)->clear();
            break;
        case 16:
            reinterpret_cast<quire16*>(quire)->clear();
            break;
        case 32:
            reinterpret_cast<quire32*>(quire)->clear();
            break;
        case 64:
            reinterpret_cast<quire64*>(quire)->clear();
            break;
        default:
        }
    }
    else // FLOAT
    {
        switch (dataWidth)
        {
        case 32:
            *reinterpret_cast<float *>(quire) = 0;
            break;
        case 64:
            *reinterpret_cast<double *>(quire) = 0;
            break;
        default:
        }
    }
}

p::UniversalTarget::~UniversalTarget()
{
    delete quire;
}
