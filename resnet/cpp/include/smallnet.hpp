#pragma once

#include <positnn/activation/ReLU.hpp>
#include <positnn/layer/Layer.hpp>
#include <positnn/layer/Linear.hpp>
#include <positnn/tensor/StdTensor.hpp>

// One-hidden-layer FC network for MNIST.
//
// Parameter layout matches SmallNet in src/models/smallnet.py:
//   fc1 | fc2  (4 tensors total, weight then bias each)

constexpr int HIDDEN_NEURONS = 32;

template<typename T>
class SmallNetPosit : public Layer<typename T::Optimizer> {
    using O = typename T::Optimizer;
    using F = typename T::Forward;
    using B = typename T::Backward;
    using G = typename T::Gradient;

    Linear<O, F, B, G> fc1, fc2;
    ReLU relu;

public:
    SmallNetPosit(size_t num_classes = 10) :
        fc1(784, HIDDEN_NEURONS),
        fc2(HIDDEN_NEURONS, num_classes)
    {
        this->register_module(fc1);
        this->register_module(fc2);
    }

    StdTensor<F> forward(StdTensor<F> x) {
        x.reshape({x.shape()[0], 784});
        x = relu.forward(fc1.forward(x));
        return fc2.forward(x);
    }

    StdTensor<B> backward(StdTensor<B> delta) {
        delta = fc2.backward(delta);
        delta = fc1.backward(relu.backward(delta));
        return delta;
    }
};
