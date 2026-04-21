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

        virtual Number toNumber(float f) = 0;
        virtual Number toNumber(double d) = 0;
        virtual Number toNumber(int32_t i) = 0;
        virtual Number toNumber(uint32_t i) = 0;
        virtual Number toNumber(int64_t i) = 0;
        virtual Number toNumber(uint64_t i) = 0;
        virtual float toFloat(Number n) = 0;
        virtual double toDouble(Number n) = 0;
        virtual int32_t toInt32(Number n) = 0;
        virtual uint32_t toUint32(Number n) = 0;
        virtual int64_t toInt64(Number n) = 0;
        virtual uint64_t toUint64(Number n) = 0;
        virtual std::string toString(Number n) = 0;

        virtual Number add(Number a, Number b) = 0;
        virtual Number sub(Number a, Number b) = 0;
        virtual Number mul(Number a, Number b) = 0;
        virtual Number div(Number a, Number b) = 0;
        virtual Number neg(Number a) = 0;
        virtual Number abs(Number a) = 0;
        virtual Number sqrt(Number a) = 0;
        virtual Number relu(Number a) = 0;

        virtual void qaClear() = 0;
        virtual void qaAdd(Number a) = 0;
        virtual void qaFma(Number a, Number b) = 0;
        virtual void qaFms(Number a, Number b) = 0;
        virtual void qaNeg() = 0;
        virtual Number qaRead() = 0;

        virtual ~Target() = default;
    };

    class UniversalTarget : public Target
    {
        void *quire;

    public:
        UniversalTarget(int dataWidth, Datatype dataType = POSIT);


        virtual Number toNumber(float f) = 0;
        virtual Number toNumber(double d) = 0;
        virtual Number toNumber(int32_t i) = 0;
        virtual Number toNumber(uint32_t i) = 0;
        virtual Number toNumber(int64_t i) = 0;
        virtual Number toNumber(uint64_t i) = 0;
        virtual float toFloat(Number n) = 0;
        virtual double toDouble(Number n) = 0;
        virtual int32_t toInt32(Number n) = 0;
        virtual uint32_t toUint32(Number n) = 0;
        virtual int64_t toInt64(Number n) = 0;
        virtual uint64_t toUint64(Number n) = 0;
        virtual std::string toString(Number n) = 0;

        virtual Number add(Number a, Number b) = 0;
        virtual Number sub(Number a, Number b) = 0;
        virtual Number mul(Number a, Number b) = 0;
        virtual Number div(Number a, Number b) = 0;
        virtual Number neg(Number a) = 0;
        virtual Number abs(Number a) = 0;
        virtual Number sqrt(Number a) = 0;
        virtual Number relu(Number a) = 0;

        void qaClear() override;
        virtual void qaAdd(Number a) = 0;
        virtual void qaFma(Number a, Number b) = 0;
        virtual void qaFms(Number a, Number b) = 0;
        virtual void qaNeg() = 0;
        virtual Number qaRead() = 0;

        ~UniversalTarget() override;
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
