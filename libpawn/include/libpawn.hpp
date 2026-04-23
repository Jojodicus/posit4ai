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
    protected:
        void *quire;
        UniversalTarget(uint32_t dataWidth);

    public:
        virtual ~UniversalTarget();
    };

    class FloatTarget : public Target
    {
    protected:
        void *acc;
        FloatTarget(uint32_t dataWidth);

    public:
        virtual ~FloatTarget();
    };

    class Posit8Target final : public UniversalTarget
    {
    public:
        Posit8Target();
    };
    class Posit16Target final : public UniversalTarget
    {
    public:
        Posit16Target();
    };
    class Posit32Target final : public UniversalTarget
    {
    public:
        Posit32Target();
    };
    class Posit64Target final : public UniversalTarget
    {
    public:
        Posit64Target();
    };

    class Float32Target final : public FloatTarget
    {
    public:
        Float32Target();
        Number toNumber(float f) override;
        Number toNumber(double d) override;
        Number toNumber(int32_t i) override;
        Number toNumber(uint32_t i) override;
        Number toNumber(int64_t i) override;
        Number toNumber(uint64_t i) override;
        float toFloat(Number n) override;
        double toDouble(Number n) override;
        int32_t toInt32(Number n) override;
        uint32_t toUint32(Number n) override;
        int64_t toInt64(Number n) override;
        uint64_t toUint64(Number n) override;
        std::string toString(Number n) override;
        Number add(Number a, Number b) override;
        Number sub(Number a, Number b) override;
        Number mul(Number a, Number b) override;
        Number div(Number a, Number b) override;
        Number neg(Number a) override;
        Number abs(Number a) override;
        Number sqrt(Number a) override;
        Number relu(Number a) override;
        void qaClear() override;
        void qaAdd(Number a) override;
        void qaFma(Number a, Number b) override;
        void qaFms(Number a, Number b) override;
        void qaNeg() override;
        Number qaRead() override;
    };
    class Float64Target final : public FloatTarget
    {
    public:
        Float64Target();
        Number toNumber(float f) override;
        Number toNumber(double d) override;
        Number toNumber(int32_t i) override;
        Number toNumber(uint32_t i) override;
        Number toNumber(int64_t i) override;
        Number toNumber(uint64_t i) override;
        float toFloat(Number n) override;
        double toDouble(Number n) override;
        int32_t toInt32(Number n) override;
        uint32_t toUint32(Number n) override;
        int64_t toInt64(Number n) override;
        uint64_t toUint64(Number n) override;
        std::string toString(Number n) override;
        Number add(Number a, Number b) override;
        Number sub(Number a, Number b) override;
        Number mul(Number a, Number b) override;
        Number div(Number a, Number b) override;
        Number neg(Number a) override;
        Number abs(Number a) override;
        Number sqrt(Number a) override;
        Number relu(Number a) override;
        void qaClear() override;
        void qaAdd(Number a) override;
        void qaFma(Number a, Number b) override;
        void qaFms(Number a, Number b) override;
        void qaNeg() override;
        Number qaRead() override;
    };

    class Bfloat16Target final : public FloatTarget
    {
    public:
        Bfloat16Target();
        Number toNumber(float f) override;
        Number toNumber(double d) override;
        Number toNumber(int32_t i) override;
        Number toNumber(uint32_t i) override;
        Number toNumber(int64_t i) override;
        Number toNumber(uint64_t i) override;
        float toFloat(Number n) override;
        double toDouble(Number n) override;
        int32_t toInt32(Number n) override;
        uint32_t toUint32(Number n) override;
        int64_t toInt64(Number n) override;
        uint64_t toUint64(Number n) override;
        std::string toString(Number n) override;
        Number add(Number a, Number b) override;
        Number sub(Number a, Number b) override;
        Number mul(Number a, Number b) override;
        Number div(Number a, Number b) override;
        Number neg(Number a) override;
        Number abs(Number a) override;
        Number sqrt(Number a) override;
        Number relu(Number a) override;
        void qaClear() override;
        void qaAdd(Number a) override;
        void qaFma(Number a, Number b) override;
        void qaFms(Number a, Number b) override;
        void qaNeg() override;
        Number qaRead() override;
    };

    class Tfloat32Target final : public FloatTarget
    {
    public:
        Tfloat32Target();
        Number toNumber(float f) override;
        Number toNumber(double d) override;
        Number toNumber(int32_t i) override;
        Number toNumber(uint32_t i) override;
        Number toNumber(int64_t i) override;
        Number toNumber(uint64_t i) override;
        float toFloat(Number n) override;
        double toDouble(Number n) override;
        int32_t toInt32(Number n) override;
        uint32_t toUint32(Number n) override;
        int64_t toInt64(Number n) override;
        uint64_t toUint64(Number n) override;
        std::string toString(Number n) override;
        Number add(Number a, Number b) override;
        Number sub(Number a, Number b) override;
        Number mul(Number a, Number b) override;
        Number div(Number a, Number b) override;
        Number neg(Number a) override;
        Number abs(Number a) override;
        Number sqrt(Number a) override;
        Number relu(Number a) override;
        void qaClear() override;
        void qaAdd(Number a) override;
        void qaFma(Number a, Number b) override;
        void qaFms(Number a, Number b) override;
        void qaNeg() override;
        Number qaRead() override;
    };

    class Takum12Target final : public FloatTarget
    {
    public:
        Takum12Target();
        Number toNumber(float f) override;
        Number toNumber(double d) override;
        Number toNumber(int32_t i) override;
        Number toNumber(uint32_t i) override;
        Number toNumber(int64_t i) override;
        Number toNumber(uint64_t i) override;
        float toFloat(Number n) override;
        double toDouble(Number n) override;
        int32_t toInt32(Number n) override;
        uint32_t toUint32(Number n) override;
        int64_t toInt64(Number n) override;
        uint64_t toUint64(Number n) override;
        std::string toString(Number n) override;
        Number add(Number a, Number b) override;
        Number sub(Number a, Number b) override;
        Number mul(Number a, Number b) override;
        Number div(Number a, Number b) override;
        Number neg(Number a) override;
        Number abs(Number a) override;
        Number sqrt(Number a) override;
        Number relu(Number a) override;
        void qaClear() override;
        void qaAdd(Number a) override;
        void qaFma(Number a, Number b) override;
        void qaFms(Number a, Number b) override;
        void qaNeg() override;
        Number qaRead() override;
    };

    class Takum16Target final : public FloatTarget
    {
    public:
        Takum16Target();
        Number toNumber(float f) override;
        Number toNumber(double d) override;
        Number toNumber(int32_t i) override;
        Number toNumber(uint32_t i) override;
        Number toNumber(int64_t i) override;
        Number toNumber(uint64_t i) override;
        float toFloat(Number n) override;
        double toDouble(Number n) override;
        int32_t toInt32(Number n) override;
        uint32_t toUint32(Number n) override;
        int64_t toInt64(Number n) override;
        uint64_t toUint64(Number n) override;
        std::string toString(Number n) override;
        Number add(Number a, Number b) override;
        Number sub(Number a, Number b) override;
        Number mul(Number a, Number b) override;
        Number div(Number a, Number b) override;
        Number neg(Number a) override;
        Number abs(Number a) override;
        Number sqrt(Number a) override;
        Number relu(Number a) override;
        void qaClear() override;
        void qaAdd(Number a) override;
        void qaFma(Number a, Number b) override;
        void qaFms(Number a, Number b) override;
        void qaNeg() override;
        Number qaRead() override;
    };

    class Takum32Target final : public FloatTarget
    {
    public:
        Takum32Target();
        Number toNumber(float f) override;
        Number toNumber(double d) override;
        Number toNumber(int32_t i) override;
        Number toNumber(uint32_t i) override;
        Number toNumber(int64_t i) override;
        Number toNumber(uint64_t i) override;
        float toFloat(Number n) override;
        double toDouble(Number n) override;
        int32_t toInt32(Number n) override;
        uint32_t toUint32(Number n) override;
        int64_t toInt64(Number n) override;
        uint64_t toUint64(Number n) override;
        std::string toString(Number n) override;
        Number add(Number a, Number b) override;
        Number sub(Number a, Number b) override;
        Number mul(Number a, Number b) override;
        Number div(Number a, Number b) override;
        Number neg(Number a) override;
        Number abs(Number a) override;
        Number sqrt(Number a) override;
        Number relu(Number a) override;
        void qaClear() override;
        void qaAdd(Number a) override;
        void qaFma(Number a, Number b) override;
        void qaFms(Number a, Number b) override;
        void qaNeg() override;
        Number qaRead() override;
    };

    class Takum48Target final : public FloatTarget
    {
    public:
        Takum48Target();
        Number toNumber(float f) override;
        Number toNumber(double d) override;
        Number toNumber(int32_t i) override;
        Number toNumber(uint32_t i) override;
        Number toNumber(int64_t i) override;
        Number toNumber(uint64_t i) override;
        float toFloat(Number n) override;
        double toDouble(Number n) override;
        int32_t toInt32(Number n) override;
        uint32_t toUint32(Number n) override;
        int64_t toInt64(Number n) override;
        uint64_t toUint64(Number n) override;
        std::string toString(Number n) override;
        Number add(Number a, Number b) override;
        Number sub(Number a, Number b) override;
        Number mul(Number a, Number b) override;
        Number div(Number a, Number b) override;
        Number neg(Number a) override;
        Number abs(Number a) override;
        Number sqrt(Number a) override;
        Number relu(Number a) override;
        void qaClear() override;
        void qaAdd(Number a) override;
        void qaFma(Number a, Number b) override;
        void qaFms(Number a, Number b) override;
        void qaNeg() override;
        Number qaRead() override;
    };

    class XpositTarget final : public Target
    {
    public:
        XpositTarget();
    };

    class PawnTarget : public Target
    {
    public:
        PawnTarget(int dataWidth, uint32_t instrDepth, uint32_t dataDepth, Datatype dataType = POSIT);
    };
}