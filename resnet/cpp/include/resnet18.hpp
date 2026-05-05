#pragma once

#include <positnn/activation/ReLU.hpp>
#include <positnn/layer/AvgPool2d.hpp>
#include <positnn/layer/Conv2d.hpp>
#include <positnn/layer/Layer.hpp>
#include <positnn/layer/Linear.hpp>
#include <positnn/tensor/StdTensor.hpp>

// ---- BasicBlock (identity shortcut: in_ch == out_ch, stride == 1) -----------

template<typename T>
class BasicBlockIdentity : public Layer<typename T::Optimizer> {
    using O = typename T::Optimizer;
    using F = typename T::Forward;
    using B = typename T::Backward;
    using G = typename T::Gradient;

    Conv2d<O, F, B, G> conv1, conv2;
    ReLU relu1, relu2;

public:
    BasicBlockIdentity(size_t ch) :
        conv1(ch, ch, 3, 1, 1),
        conv2(ch, ch, 3, 1, 1)
    {
        this->register_module(conv1);
        this->register_module(conv2);
    }

    StdTensor<F> forward(StdTensor<F> x) {
        StdTensor<F> residual = x;
        x = relu1.forward(conv1.forward(x));
        x = conv2.forward(x);
        x = x + residual;
        return relu2.forward(x);
    }

    StdTensor<B> backward(StdTensor<B> delta) {
        delta = relu2.backward(delta);
        StdTensor<B> delta_res = delta;
        delta = conv2.backward(delta);
        delta = conv1.backward(relu1.backward(delta));
        return delta + delta_res;
    }
};

// ---- BasicBlock (projection shortcut: stride > 1 or channel change) ---------

template<typename T>
class BasicBlockProjection : public Layer<typename T::Optimizer> {
    using O = typename T::Optimizer;
    using F = typename T::Forward;
    using B = typename T::Backward;
    using G = typename T::Gradient;

    Conv2d<O, F, B, G> conv1, conv2, shortcut;
    ReLU relu1, relu2;

public:
    BasicBlockProjection(size_t in_ch, size_t out_ch, size_t stride) :
        conv1(in_ch, out_ch, 3, stride, 1),
        conv2(out_ch, out_ch, 3, 1, 1),
        shortcut(in_ch, out_ch, 1, stride, 0)
    {
        this->register_module(conv1);
        this->register_module(conv2);
        this->register_module(shortcut);
    }

    StdTensor<F> forward(StdTensor<F> x) {
        StdTensor<F> residual = shortcut.forward(x);
        x = relu1.forward(conv1.forward(x));
        x = conv2.forward(x);
        x = x + residual;
        return relu2.forward(x);
    }

    StdTensor<B> backward(StdTensor<B> delta) {
        delta = relu2.backward(delta);
        StdTensor<B> delta_sc = shortcut.backward(delta);
        delta = conv2.backward(delta);
        delta = conv1.backward(relu1.backward(delta));
        return delta + delta_sc;
    }
};

// ---- ResNet-18 (CIFAR variant, BN-fused) ------------------------------------
//
// Parameter layout matches ResNet18Fused in src/models/resnet18_fused.py.
// Use copy_parameters() to transfer weights from the Python-exported TorchScript.
//
// Registration order (each Conv2d contributes weight then bias):
//   stem | l1_0 | l1_1 | l2_0(+shortcut) | l2_1 | ... | l4_1 | fc

template<typename T>
class ResNet18Posit : public Layer<typename T::Optimizer> {
    using O = typename T::Optimizer;
    using F = typename T::Forward;
    using B = typename T::Backward;
    using G = typename T::Gradient;

    Conv2d<O, F, B, G> stem;
    ReLU stem_relu;

    BasicBlockIdentity<T>    l1_0, l1_1;
    BasicBlockProjection<T>  l2_0;
    BasicBlockIdentity<T>    l2_1;
    BasicBlockProjection<T>  l3_0;
    BasicBlockIdentity<T>    l3_1;
    BasicBlockProjection<T>  l4_0;
    BasicBlockIdentity<T>    l4_1;

    // GAP: 32x32 -> 16 -> 8 -> 4 after three stride-2 layers; pool 4x4
    // AvgPool2d constructor bug: pass stride=0 to trigger stride = kernel_size
    AvgPool2d<F> gap;

    Linear<O, F, B, G> fc;

public:
    ResNet18Posit(size_t num_classes = 10) :
        stem(3, 64, 3, 1, 1),
        l1_0(64), l1_1(64),
        l2_0(64, 128, 2), l2_1(128),
        l3_0(128, 256, 2), l3_1(256),
        l4_0(256, 512, 2), l4_1(512),
        gap(4, 0),
        fc(512, num_classes)
    {
        this->register_module(stem);
        this->register_module(l1_0);
        this->register_module(l1_1);
        this->register_module(l2_0);
        this->register_module(l2_1);
        this->register_module(l3_0);
        this->register_module(l3_1);
        this->register_module(l4_0);
        this->register_module(l4_1);
        this->register_module(fc);
    }

    StdTensor<F> forward(StdTensor<F> x) {
        x = stem_relu.forward(stem.forward(x));
        x = l1_0.forward(x);
        x = l1_1.forward(x);
        x = l2_0.forward(x);
        x = l2_1.forward(x);
        x = l3_0.forward(x);
        x = l3_1.forward(x);
        x = l4_0.forward(x);
        x = l4_1.forward(x);
        x = gap.forward(x);
        x.reshape({x.shape()[0], 512});
        return fc.forward(x);
    }

    StdTensor<B> backward(StdTensor<B> delta) {
        delta = fc.backward(delta);
        delta.reshape({delta.shape()[0], 512, 1, 1});
        delta = gap.backward(delta);
        delta = l4_1.backward(delta);
        delta = l4_0.backward(delta);
        delta = l3_1.backward(delta);
        delta = l3_0.backward(delta);
        delta = l2_1.backward(delta);
        delta = l2_0.backward(delta);
        delta = l1_1.backward(delta);
        delta = l1_0.backward(delta);
        delta = stem.backward(stem_relu.backward(delta));
        return delta;
    }
};
