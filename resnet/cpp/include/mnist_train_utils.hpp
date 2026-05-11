#pragma once

// Shared utilities for posit training on MNIST: eval and train-epoch.
// Mirrors posit_train_utils.hpp but uses torch::data::datasets::MNIST
// instead of Cifar10Data, and omits CIFAR-specific augmentation.

#include <cmath>
#include <cstdio>
#include <string>

#include <torch/torch.h>
#include <universal/posit/posit>
#include <positnn/positnn>

#include "posit_types.hpp"

static const float MNIST_MEAN = 0.1307f;
static const float MNIST_STD  = 0.3081f;

// Evaluate posit model on MNIST test set. Returns (accuracy, mean_nll).
template<typename PT, template<typename> class ModelT>
std::pair<float, float> eval_posit_mnist(ModelT<PT>& model, const std::string& data_path) {
    using F = typename PT::Forward;

    auto test_dataset =
        torch::data::datasets::MNIST(
            data_path, torch::data::datasets::MNIST::Mode::kTest)
        .map(torch::data::transforms::Normalize<>(MNIST_MEAN, MNIST_STD))
        .map(torch::data::transforms::Stack<>());
    const size_t n_test = test_dataset.size().value();

    auto loader = torch::data::make_data_loader(
        std::move(test_dataset),
        torch::data::DataLoaderOptions().batch_size(512));

    model.eval();
    size_t correct   = 0;
    float  total_nll = 0.f;

    for (auto& batch : *loader) {
        auto data   = batch.data.to(torch::kFloat32);
        auto target = batch.target;

        auto posit_in  = Tensor_to_StdTensor<float, F>(data);
        auto posit_out = model.forward(posit_in);
        auto out_f32   = StdTensor_to_Tensor<float, torch::kFloat32, F>(posit_out);

        auto log_probs = torch::log_softmax(out_f32, 1);
        auto nll       = torch::nll_loss(log_probs, target, {}, torch::Reduction::Sum);

        correct   += out_f32.argmax(1).eq(target).sum().template item<int64_t>();
        total_nll += nll.template item<float>();
    }

    model.train();
    return {static_cast<float>(correct) / n_test, total_nll / n_test};
}

// One training epoch on MNIST (no augmentation). Returns {mean_batch_loss, accuracy}.
template<typename PT, template<typename> class ModelT, typename SGDType, typename DataLoader>
std::pair<float, float> train_epoch_posit_mnist(
    ModelT<PT>&  model,
    DataLoader&  train_loader,
    SGDType&     optimizer,
    size_t       epoch,
    size_t       num_epochs,
    float        lr_max
) {
    using F = typename PT::Forward;
    using O = typename PT::Optimizer;

    float lr = lr_max * 0.5f * (1.f + std::cos(
        static_cast<float>(M_PI) * float(epoch - 1) / float(num_epochs)));
    optimizer.options().learning_rate = O(lr);

    model.train();
    float  total_loss = 0.f;
    size_t batches    = 0;
    size_t correct    = 0;
    size_t total      = 0;

    for (auto& batch : train_loader) {
        auto data_f32  = batch.data.to(torch::kFloat32);
        auto target_u8 = batch.target.to(torch::kUInt8);

        auto data   = Tensor_to_StdTensor<float, F>(data_f32);
        auto target = Tensor_to_StdTensor<uint8_t, unsigned short int>(target_u8);

        auto output = model.forward(data);
        cross_entropy_loss<F> loss(output, target);

        optimizer.zero_grad();
        loss.backward(model);
        optimizer.step();

        total_loss += loss.template item<float>();
        batches++;

        auto out_f32 = StdTensor_to_Tensor<float, torch::kFloat32, F>(output);
        auto tgt_i64 = batch.target.to(torch::kInt64);
        correct += out_f32.argmax(1).eq(tgt_i64).sum().template item<int64_t>();
        total   += batch.target.size(0);
    }
    float acc = (total > 0) ? static_cast<float>(correct) / total : 0.f;
    return {(batches > 0) ? total_loss / batches : 0.f, acc};
}
