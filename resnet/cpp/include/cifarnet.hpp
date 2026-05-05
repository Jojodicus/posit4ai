#pragma once

#include <positnn/activation/ReLU.hpp>
#include <positnn/layer/Conv2d.hpp>
#include <positnn/layer/Layer.hpp>
#include <positnn/layer/Linear.hpp>
#include <positnn/layer/MaxPool2d.hpp>
#include <positnn/tensor/StdTensor.hpp>

// Small conv-net for CIFAR-10.
//
// Parameter layout matches CifarNet in src/models/cifarnet.py:
//   conv1 | conv2 | fc1 | fc2 | fc3  (10 tensors total, weight then bias each)

template<typename T>
class CifarNetPosit : public Layer<typename T::Optimizer> {
    using O = typename T::Optimizer;
    using F = typename T::Forward;
    using B = typename T::Backward;
    using G = typename T::Gradient;

    Conv2d<O, F, B, G> conv1, conv2;
    MaxPool2d<F>        pool1, pool2;
    Linear<O, F, B, G> fc1, fc2, fc3;
    ReLU relu1, relu2, relu3, relu4;

public:
    CifarNetPosit(size_t num_classes = 10) :
        conv1(3, 8, 5, 1, 2),
        conv2(8, 16, 5, 1, 2),
        pool1(2, 0),
        pool2(2, 0),
        fc1(1024, 384),
        fc2(384, 192),
        fc3(192, num_classes)
    {
        this->register_module(conv1);
        this->register_module(conv2);
        this->register_module(fc1);
        this->register_module(fc2);
        this->register_module(fc3);
    }

    StdTensor<F> forward(StdTensor<F> x) {
        x = relu1.forward(pool1.forward(conv1.forward(x)));
        x = relu2.forward(pool2.forward(conv2.forward(x)));
        x.reshape({x.shape()[0], 1024});
        x = relu3.forward(fc1.forward(x));
        x = relu4.forward(fc2.forward(x));
        return fc3.forward(x);
    }

    StdTensor<B> backward(StdTensor<B> delta) {
        delta = fc3.backward(delta);
        delta = fc2.backward(relu4.backward(delta));
        delta = fc1.backward(relu3.backward(delta));
        delta.reshape({delta.shape()[0], 16, 8, 8});
        delta = conv2.backward(pool2.backward(relu2.backward(delta)));
        delta = conv1.backward(pool1.backward(relu1.backward(delta)));
        return delta;
    }
};
