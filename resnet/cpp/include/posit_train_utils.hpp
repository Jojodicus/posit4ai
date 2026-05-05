#pragma once

// Shared utilities for posit training: augmentation, eval, and train-epoch.

#include <cmath>
#include <cstdio>
#include <string>

#include <torch/torch.h>
#include <universal/posit/posit>
#include <positnn/positnn>

#include "Cifar10Data.hpp"
#include "posit_types.hpp"

static const float TRAIN_CIFAR_MEAN[3] = {0.4914f, 0.4822f, 0.4465f};
static const float TRAIN_CIFAR_STD[3]  = {0.2023f, 0.1994f, 0.2010f};

// Random pad-4-crop-32 + random horizontal flip in-place on a float32 batch tensor.
inline torch::Tensor augment_batch(torch::Tensor data) {
    namespace F = torch::nn::functional;
    data = F::pad(data, F::PadFuncOptions({4, 4, 4, 4}));
    for (int64_t i = 0; i < data.size(0); i++) {
        int64_t x = torch::randint(0, 8, {1}).item<int64_t>();
        int64_t y = torch::randint(0, 8, {1}).item<int64_t>();
        namespace idx = torch::indexing;
        data[i] = data.index({i,
            idx::Slice(),
            idx::Slice(y, y + 32),
            idx::Slice(x, x + 32)}).clone();
    }
    for (int64_t i = 0; i < data.size(0); i++) {
        if (torch::rand({1}).item<float>() > 0.5f)
            data[i] = data[i].flip(2);
    }
    return data;
}

// Evaluate posit model on CIFAR-10 test set. Returns (accuracy, mean_nll).
template<typename PT, template<typename> class ModelT>
std::pair<float, float> eval_posit(ModelT<PT>& model, const std::string& data_path) {
    using F = typename PT::Forward;

    auto test_dataset = Cifar10Data(data_path, false)
        .map(torch::data::transforms::Normalize<>(
            {TRAIN_CIFAR_MEAN[0], TRAIN_CIFAR_MEAN[1], TRAIN_CIFAR_MEAN[2]},
            {TRAIN_CIFAR_STD[0],  TRAIN_CIFAR_STD[1],  TRAIN_CIFAR_STD[2]}))
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

// One training epoch with cosine-annealed LR. Returns mean batch loss.
template<typename PT, template<typename> class ModelT, typename SGDType, typename DataLoader>
float train_epoch_posit(
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

    for (auto& batch : train_loader) {
        auto data_f32  = augment_batch(batch.data.to(torch::kFloat32));
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
    }
    return (batches > 0) ? total_loss / batches : 0.f;
}
