#pragma once

#include <cstdint>
#include <string>

namespace p
{
    struct Number
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
    protected:
        Target(uint32_t dataWidth, Datatype dataType);

    public:
        const uint32_t dataWidth;
        const Datatype dataType;

        virtual Number toNumber(float f) { return Number{}; }
        virtual Number toNumber(double d) { return Number{}; }
        virtual Number toNumber(int32_t i) { return Number{}; }
        virtual Number toNumber(uint32_t i) { return Number{}; }
        virtual Number toNumber(int64_t i) { return Number{}; }
        virtual Number toNumber(uint64_t i) { return Number{}; }
        virtual float toFloat(Number n) { return 0.0f; }
        virtual double toDouble(Number n) { return 0.0; }
        virtual int32_t toInt32(Number n) { return 0; }
        virtual uint32_t toUint32(Number n) { return 0; }
        virtual int64_t toInt64(Number n) { return 0; }
        virtual uint64_t toUint64(Number n) { return 0; }
        virtual std::string toString(Number n) { return ""; }

        virtual Number add(Number a, Number b) { return Number{}; }
        virtual Number sub(Number a, Number b) { return Number{}; }
        virtual Number mul(Number a, Number b) { return Number{}; }
        virtual Number div(Number a, Number b) { return Number{}; }
        virtual Number neg(Number a) { return Number{}; }
        virtual Number abs(Number a) { return Number{}; }
        virtual Number sqrt(Number a) { return Number{}; }
        virtual Number relu(Number a) { return Number{}; }

        virtual void qaClear() {}
        virtual void qaAdd(Number a) {}
        virtual void qaFma(Number a, Number b) {}
        virtual void qaFms(Number a, Number b) {}
        virtual void qaNeg() {}
        virtual Number qaRead() { return Number{}; }

        virtual ~Target() = default;
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
