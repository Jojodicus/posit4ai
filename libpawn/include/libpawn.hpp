#pragma once

#include <stdint.h>

class PPosit {
    uint64_t bits;
};

class PTarget {
    PTarget() = delete;

    public:
    virtual PPosit toPosit(float);
    virtual PPosit toPosit(double);
    virtual float toFloat(PPosit);
    virtual double toDouble(PPosit);

    virtual PPosit add(PPosit, PPosit);
    virtual PPosit sub(PPosit, PPosit);
    virtual PPosit mul(PPosit, PPosit);
    virtual PPosit div(PPosit, PPosit);

    virtual PPosit neg(PPosit);
    virtual PPosit abs(PPosit);
    virtual PPosit sqrt(PPosit);
    virtual PPosit relu(PPosit);

    virtual void qaClear();
    virtual void qaAdd(PPosit);
    virtual void qaFma(PPosit, PPosit);
    virtual void qaFms(PPosit, PPosit);
    virtual void qaNeg();
    virtual PPosit qaRead();
};

class PSoftTarget : PTarget {

};

class PXpositTarget : PTarget {

};

class PPawnTarget : PTarget {

};


