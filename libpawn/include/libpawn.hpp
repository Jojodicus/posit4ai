#pragma once

#include <cstdint>
#include <string>
namespace p
{
    class Number
    {
        uint64_t bits;
    };

    enum Datatype
    {
        POSIT,
        FLOAT
    };

    class Target
    {
        Target() = delete;

    protected:
        Target(uint32_t dataWidth, Datatype dataType);

    public:
        const uint32_t dataWidth;
        const Datatype dataType;

        // conversions
        virtual Number toNumber(float f);
        virtual Number toNumber(double d);
        virtual Number toNumber(int32_t i);
        virtual Number toNumber(uint32_t i);
        virtual Number toNumber(int64_t i);
        virtual Number toNumber(uint64_t i);
        virtual float toFloat(Number n);
        virtual double toDouble(Number n);
        virtual int32_t toInt32(Number n);
        virtual uint32_t toUint32(Number n);
        virtual int64_t toInt64(Number n);
        virtual uint64_t toUint64(Number n);
        virtual std::string toString(Number n);

        // standard arithmetic
        virtual Number add(Number a, Number b);
        virtual Number sub(Number a, Number b);
        virtual Number mul(Number a, Number b);
        virtual Number div(Number a, Number b);
        virtual Number neg(Number a);
        virtual Number abs(Number a);
        virtual Number sqrt(Number a);
        virtual Number relu(Number a);

        // arithmetic with internal quire/accumulator
        virtual void qaClear();                 // quire  = 0
        virtual void qaAdd(Number a);           // quire  = quire + a
        virtual void qaFma(Number a, Number b); // quire  = quire + a * b
        virtual void qaFms(Number a, Number b); // quire  = quire - a * b
        virtual void qaNeg();                   // quire  = -quire
        virtual Number qaRead();                // result = round(quire)
    };

    class UniversalTarget : public Target
    {
    public:
        UniversalTarget(int dataWidth, Datatype dataType = POSIT);
    };

    class XpositTarget : public Target
    {
    public:
        XpositTarget(int dataWidth);
    };

    class PawnTarget : public Target
    {
    public:
        PawnTarget(int dataWidth, uint32_t instrDepth, uint32_t dataDepth, Datatype dataType = POSIT);
    };
}
