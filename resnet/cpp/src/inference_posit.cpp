// Posit inference sweep
//
// Usage:
//   ./inference_posit <model:resnet18|cifarnet|smallnet> <ckpt>
//                     <dtype:float|double|posit> <data_dir>
//                     <nbits> <es> <source_name> <out_csv>
//
// For resnet18/cifarnet, data_dir is the CIFAR-10 binary directory.
// For smallnet, data_dir is the MNIST directory (ubyte files).
//
// dtype=float/double: load TorchScript .pt and copy to posit model.
// dtype=posit:        load posit-native .dat checkpoint directly.
//
// Appends one row to out_csv: source,format,nbits,es,val_acc,val_nll
// format = "posit" when QUIRE_MODE==0, "positQ" when QUIRE_MODE!=0.

#include <chrono>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include <torch/script.h>
#include <torch/torch.h>
#include <universal/posit/posit>
#include <positnn/positnn>

#include "Cifar10Data.hpp"
#include "posit_types.hpp"
#include "mnist_train_utils.hpp"
#include "resnet18.hpp"
#include "cifarnet.hpp"
#include "smallnet.hpp"

static const float CIFAR_MEAN[3] = {0.4914f, 0.4822f, 0.4465f};
static const float CIFAR_STD[3]  = {0.2023f, 0.1994f, 0.2010f};

// Load from TorchScript float/double checkpoint (CIFAR-10 models).
template<size_t N, size_t E, typename FromType, template<typename> class ModelT>
std::pair<float, float> run_inference_cifar(
    const std::string& ckpt_path,
    const std::string& data_path
) {
    using PT = PType<N, E>;
    using F  = typename PT::Forward;

    auto jit_module = torch::jit::load(ckpt_path);
    jit_module.eval();

    std::vector<torch::Tensor> src_params;
    for (const auto& kv : jit_module.named_parameters())
        src_params.push_back(kv.value);

    ModelT<PT> model;
    model.eval();

    auto& dst_params = model.parameters();
    if (src_params.size() != dst_params.size()) {
        std::fprintf(stderr,
            "ERROR: parameter count mismatch: JIT=%zu posit=%zu\n",
            src_params.size(), dst_params.size());
        return {0.f, 0.f};
    }
    copy_parameters<FromType>(src_params, dst_params);

    auto test_dataset = Cifar10Data(data_path, false)
        .map(torch::data::transforms::Normalize<>(
            {CIFAR_MEAN[0], CIFAR_MEAN[1], CIFAR_MEAN[2]},
            {CIFAR_STD[0],  CIFAR_STD[1],  CIFAR_STD[2]}))
        .map(torch::data::transforms::Stack<>());
    const size_t n_test = test_dataset.size().value();

    auto loader = torch::data::make_data_loader(
        std::move(test_dataset),
        torch::data::DataLoaderOptions().batch_size(512));

    size_t correct   = 0;
    float  total_nll = 0.f;
    size_t seen      = 0;

    auto t0 = std::chrono::steady_clock::now();
    for (auto& batch : *loader) {
        auto data   = batch.data.to(torch::kFloat32);
        auto target = batch.target;

        auto posit_in  = Tensor_to_StdTensor<float, F>(data);
        auto posit_out = model.forward(posit_in);
        auto out_f32   = StdTensor_to_Tensor<float, torch::kFloat32, F>(posit_out);

        auto log_probs = torch::log_softmax(out_f32, 1);
        auto loss      = torch::nll_loss(log_probs, target, {}, torch::Reduction::Sum);
        auto pred      = out_f32.argmax(1);

        size_t batch_correct = pred.eq(target).sum().template item<int64_t>();
        float  batch_nll     = loss.template item<float>();

        total_nll += batch_nll;
        correct   += batch_correct;
        seen      += target.size(0);

        std::printf("\r  [%5zu/%5zu]  batch_acc=%.4f  running_acc=%.4f",
                    seen, n_test,
                    static_cast<float>(batch_correct) / target.size(0),
                    static_cast<float>(correct) / seen);
        std::fflush(stdout);
    }
    auto t1 = std::chrono::steady_clock::now();
    double elapsed_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    std::printf("\n  inference time: %.1f ms\n", elapsed_ms);

    return {static_cast<float>(correct) / n_test, total_nll / n_test};
}

// Load from TorchScript float/double checkpoint (MNIST models).
template<size_t N, size_t E, typename FromType, template<typename> class ModelT>
std::pair<float, float> run_inference_mnist(
    const std::string& ckpt_path,
    const std::string& data_path
) {
    using PT = PType<N, E>;
    using F  = typename PT::Forward;

    auto jit_module = torch::jit::load(ckpt_path);
    jit_module.eval();

    std::vector<torch::Tensor> src_params;
    for (const auto& kv : jit_module.named_parameters())
        src_params.push_back(kv.value);

    ModelT<PT> model;
    model.eval();

    auto& dst_params = model.parameters();
    if (src_params.size() != dst_params.size()) {
        std::fprintf(stderr,
            "ERROR: parameter count mismatch: JIT=%zu posit=%zu\n",
            src_params.size(), dst_params.size());
        return {0.f, 0.f};
    }
    copy_parameters<FromType>(src_params, dst_params);

    auto test_dataset =
        torch::data::datasets::MNIST(
            data_path, torch::data::datasets::MNIST::Mode::kTest)
        .map(torch::data::transforms::Normalize<>(MNIST_MEAN, MNIST_STD))
        .map(torch::data::transforms::Stack<>());
    const size_t n_test = test_dataset.size().value();

    auto loader = torch::data::make_data_loader(
        std::move(test_dataset),
        torch::data::DataLoaderOptions().batch_size(512));

    size_t correct   = 0;
    float  total_nll = 0.f;
    size_t seen      = 0;

    auto t0 = std::chrono::steady_clock::now();
    for (auto& batch : *loader) {
        auto data   = batch.data.to(torch::kFloat32);
        auto target = batch.target;

        auto posit_in  = Tensor_to_StdTensor<float, F>(data);
        auto posit_out = model.forward(posit_in);
        auto out_f32   = StdTensor_to_Tensor<float, torch::kFloat32, F>(posit_out);

        auto log_probs = torch::log_softmax(out_f32, 1);
        auto loss      = torch::nll_loss(log_probs, target, {}, torch::Reduction::Sum);
        auto pred      = out_f32.argmax(1);

        size_t batch_correct = pred.eq(target).sum().template item<int64_t>();
        float  batch_nll     = loss.template item<float>();

        total_nll += batch_nll;
        correct   += batch_correct;
        seen      += target.size(0);

        std::printf("\r  [%5zu/%5zu]  batch_acc=%.4f  running_acc=%.4f",
                    seen, n_test,
                    static_cast<float>(batch_correct) / target.size(0),
                    static_cast<float>(correct) / seen);
        std::fflush(stdout);
    }
    auto t1 = std::chrono::steady_clock::now();
    double elapsed_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    std::printf("\n  inference time: %.1f ms\n", elapsed_ms);

    return {static_cast<float>(correct) / n_test, total_nll / n_test};
}

// Load from posit-native .dat checkpoint (CIFAR-10 models).
template<size_t N, size_t E, template<typename> class ModelT>
std::pair<float, float> run_inference_native_cifar(
    const std::string& ckpt_path,
    const std::string& data_path
) {
    using PT = PType<N, E>;
    using F  = typename PT::Forward;

    ModelT<PT> model;
    model.eval();
    if (load<posit<N, E>>(model, ckpt_path) != 0)
        return {0.f, 0.f};

    auto test_dataset = Cifar10Data(data_path, false)
        .map(torch::data::transforms::Normalize<>(
            {CIFAR_MEAN[0], CIFAR_MEAN[1], CIFAR_MEAN[2]},
            {CIFAR_STD[0],  CIFAR_STD[1],  CIFAR_STD[2]}))
        .map(torch::data::transforms::Stack<>());
    const size_t n_test = test_dataset.size().value();

    auto loader = torch::data::make_data_loader(
        std::move(test_dataset),
        torch::data::DataLoaderOptions().batch_size(512));

    size_t correct   = 0;
    float  total_nll = 0.f;
    size_t seen      = 0;

    auto t0 = std::chrono::steady_clock::now();
    for (auto& batch : *loader) {
        auto data   = batch.data.to(torch::kFloat32);
        auto target = batch.target;

        auto posit_in  = Tensor_to_StdTensor<float, F>(data);
        auto posit_out = model.forward(posit_in);
        auto out_f32   = StdTensor_to_Tensor<float, torch::kFloat32, F>(posit_out);

        auto log_probs = torch::log_softmax(out_f32, 1);
        auto nll       = torch::nll_loss(log_probs, target, {}, torch::Reduction::Sum);

        size_t batch_correct = out_f32.argmax(1).eq(target).sum().template item<int64_t>();

        total_nll += nll.template item<float>();
        correct   += batch_correct;
        seen      += target.size(0);

        std::printf("\r  [%5zu/%5zu]  batch_acc=%.4f  running_acc=%.4f",
                    seen, n_test,
                    static_cast<float>(batch_correct) / target.size(0),
                    static_cast<float>(correct) / seen);
        std::fflush(stdout);
    }
    auto t1 = std::chrono::steady_clock::now();
    double elapsed_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    std::printf("\n  inference time: %.1f ms\n", elapsed_ms);

    return {static_cast<float>(correct) / n_test, total_nll / n_test};
}

// Load from posit-native .dat checkpoint (MNIST models).
template<size_t N, size_t E, template<typename> class ModelT>
std::pair<float, float> run_inference_native_mnist(
    const std::string& ckpt_path,
    const std::string& data_path
) {
    using PT = PType<N, E>;
    using F  = typename PT::Forward;

    ModelT<PT> model;
    model.eval();
    if (load<posit<N, E>>(model, ckpt_path) != 0)
        return {0.f, 0.f};

    auto test_dataset =
        torch::data::datasets::MNIST(
            data_path, torch::data::datasets::MNIST::Mode::kTest)
        .map(torch::data::transforms::Normalize<>(MNIST_MEAN, MNIST_STD))
        .map(torch::data::transforms::Stack<>());
    const size_t n_test = test_dataset.size().value();

    auto loader = torch::data::make_data_loader(
        std::move(test_dataset),
        torch::data::DataLoaderOptions().batch_size(512));

    size_t correct   = 0;
    float  total_nll = 0.f;
    size_t seen      = 0;

    auto t0 = std::chrono::steady_clock::now();
    for (auto& batch : *loader) {
        auto data   = batch.data.to(torch::kFloat32);
        auto target = batch.target;

        auto posit_in  = Tensor_to_StdTensor<float, F>(data);
        auto posit_out = model.forward(posit_in);
        auto out_f32   = StdTensor_to_Tensor<float, torch::kFloat32, F>(posit_out);

        auto log_probs = torch::log_softmax(out_f32, 1);
        auto nll       = torch::nll_loss(log_probs, target, {}, torch::Reduction::Sum);

        size_t batch_correct = out_f32.argmax(1).eq(target).sum().template item<int64_t>();

        total_nll += nll.template item<float>();
        correct   += batch_correct;
        seen      += target.size(0);

        std::printf("\r  [%5zu/%5zu]  batch_acc=%.4f  running_acc=%.4f",
                    seen, n_test,
                    static_cast<float>(batch_correct) / target.size(0),
                    static_cast<float>(correct) / seen);
        std::fflush(stdout);
    }
    auto t1 = std::chrono::steady_clock::now();
    double elapsed_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    std::printf("\n  inference time: %.1f ms\n", elapsed_ms);

    return {static_cast<float>(correct) / n_test, total_nll / n_test};
}

// ---- dispatch tables ----

template<typename FromType, template<typename> class ModelT>
std::pair<float, float> dispatch_cifar(
    int nbits, int es,
    const std::string& ckpt, const std::string& data
) {
    if (nbits == 8  && es == 1) return run_inference_cifar<8,  1, FromType, ModelT>(ckpt, data);
    if (nbits == 8  && es == 2) return run_inference_cifar<8,  2, FromType, ModelT>(ckpt, data);
    if (nbits == 8  && es == 3) return run_inference_cifar<8,  3, FromType, ModelT>(ckpt, data);
    if (nbits == 16 && es == 1) return run_inference_cifar<16, 1, FromType, ModelT>(ckpt, data);
    if (nbits == 16 && es == 2) return run_inference_cifar<16, 2, FromType, ModelT>(ckpt, data);
    if (nbits == 16 && es == 3) return run_inference_cifar<16, 3, FromType, ModelT>(ckpt, data);
    if (nbits == 32 && es == 1) return run_inference_cifar<32, 1, FromType, ModelT>(ckpt, data);
    if (nbits == 32 && es == 2) return run_inference_cifar<32, 2, FromType, ModelT>(ckpt, data);
    if (nbits == 32 && es == 3) return run_inference_cifar<32, 3, FromType, ModelT>(ckpt, data);
    if (nbits == 64 && es == 1) return run_inference_cifar<64, 1, FromType, ModelT>(ckpt, data);
    if (nbits == 64 && es == 2) return run_inference_cifar<64, 2, FromType, ModelT>(ckpt, data);
    if (nbits == 64 && es == 3) return run_inference_cifar<64, 3, FromType, ModelT>(ckpt, data);
    std::fprintf(stderr, "ERROR: unsupported nbits=%d es=%d\n", nbits, es);
    return {0.f, 0.f};
}

template<typename FromType, template<typename> class ModelT>
std::pair<float, float> dispatch_mnist(
    int nbits, int es,
    const std::string& ckpt, const std::string& data
) {
    if (nbits == 8  && es == 1) return run_inference_mnist<8,  1, FromType, ModelT>(ckpt, data);
    if (nbits == 8  && es == 2) return run_inference_mnist<8,  2, FromType, ModelT>(ckpt, data);
    if (nbits == 8  && es == 3) return run_inference_mnist<8,  3, FromType, ModelT>(ckpt, data);
    if (nbits == 16 && es == 1) return run_inference_mnist<16, 1, FromType, ModelT>(ckpt, data);
    if (nbits == 16 && es == 2) return run_inference_mnist<16, 2, FromType, ModelT>(ckpt, data);
    if (nbits == 16 && es == 3) return run_inference_mnist<16, 3, FromType, ModelT>(ckpt, data);
    if (nbits == 32 && es == 1) return run_inference_mnist<32, 1, FromType, ModelT>(ckpt, data);
    if (nbits == 32 && es == 2) return run_inference_mnist<32, 2, FromType, ModelT>(ckpt, data);
    if (nbits == 32 && es == 3) return run_inference_mnist<32, 3, FromType, ModelT>(ckpt, data);
    if (nbits == 64 && es == 1) return run_inference_mnist<64, 1, FromType, ModelT>(ckpt, data);
    if (nbits == 64 && es == 2) return run_inference_mnist<64, 2, FromType, ModelT>(ckpt, data);
    if (nbits == 64 && es == 3) return run_inference_mnist<64, 3, FromType, ModelT>(ckpt, data);
    std::fprintf(stderr, "ERROR: unsupported nbits=%d es=%d\n", nbits, es);
    return {0.f, 0.f};
}

template<template<typename> class ModelT>
std::pair<float, float> dispatch_native_cifar(
    int nbits, int es,
    const std::string& ckpt, const std::string& data
) {
    if (nbits == 8  && es == 1) return run_inference_native_cifar<8,  1, ModelT>(ckpt, data);
    if (nbits == 8  && es == 2) return run_inference_native_cifar<8,  2, ModelT>(ckpt, data);
    if (nbits == 8  && es == 3) return run_inference_native_cifar<8,  3, ModelT>(ckpt, data);
    if (nbits == 16 && es == 1) return run_inference_native_cifar<16, 1, ModelT>(ckpt, data);
    if (nbits == 16 && es == 2) return run_inference_native_cifar<16, 2, ModelT>(ckpt, data);
    if (nbits == 16 && es == 3) return run_inference_native_cifar<16, 3, ModelT>(ckpt, data);
    if (nbits == 32 && es == 1) return run_inference_native_cifar<32, 1, ModelT>(ckpt, data);
    if (nbits == 32 && es == 2) return run_inference_native_cifar<32, 2, ModelT>(ckpt, data);
    if (nbits == 32 && es == 3) return run_inference_native_cifar<32, 3, ModelT>(ckpt, data);
    if (nbits == 64 && es == 1) return run_inference_native_cifar<64, 1, ModelT>(ckpt, data);
    if (nbits == 64 && es == 2) return run_inference_native_cifar<64, 2, ModelT>(ckpt, data);
    if (nbits == 64 && es == 3) return run_inference_native_cifar<64, 3, ModelT>(ckpt, data);
    std::fprintf(stderr, "ERROR: unsupported nbits=%d es=%d\n", nbits, es);
    return {0.f, 0.f};
}

template<template<typename> class ModelT>
std::pair<float, float> dispatch_native_mnist(
    int nbits, int es,
    const std::string& ckpt, const std::string& data
) {
    if (nbits == 8  && es == 1) return run_inference_native_mnist<8,  1, ModelT>(ckpt, data);
    if (nbits == 8  && es == 2) return run_inference_native_mnist<8,  2, ModelT>(ckpt, data);
    if (nbits == 8  && es == 3) return run_inference_native_mnist<8,  3, ModelT>(ckpt, data);
    if (nbits == 16 && es == 1) return run_inference_native_mnist<16, 1, ModelT>(ckpt, data);
    if (nbits == 16 && es == 2) return run_inference_native_mnist<16, 2, ModelT>(ckpt, data);
    if (nbits == 16 && es == 3) return run_inference_native_mnist<16, 3, ModelT>(ckpt, data);
    if (nbits == 32 && es == 1) return run_inference_native_mnist<32, 1, ModelT>(ckpt, data);
    if (nbits == 32 && es == 2) return run_inference_native_mnist<32, 2, ModelT>(ckpt, data);
    if (nbits == 32 && es == 3) return run_inference_native_mnist<32, 3, ModelT>(ckpt, data);
    if (nbits == 64 && es == 1) return run_inference_native_mnist<64, 1, ModelT>(ckpt, data);
    if (nbits == 64 && es == 2) return run_inference_native_mnist<64, 2, ModelT>(ckpt, data);
    if (nbits == 64 && es == 3) return run_inference_native_mnist<64, 3, ModelT>(ckpt, data);
    std::fprintf(stderr, "ERROR: unsupported nbits=%d es=%d\n", nbits, es);
    return {0.f, 0.f};
}

#if QUIRE_MODE != 0
static const char* POSIT_FORMAT = "positQ";
#else
static const char* POSIT_FORMAT = "posit";
#endif

int main(int argc, char* argv[]) {
    if (argc != 9) {
        std::fprintf(stderr,
            "Usage: %s <model:resnet18|cifarnet|smallnet> <ckpt>"
            " <dtype:float|double|posit> <data_dir>"
            " <nbits> <es> <source_name> <out_csv>\n",
            argv[0]);
        return 1;
    }

    std::string model_name = argv[1];
    std::string ckpt       = argv[2];
    std::string dtype      = argv[3];
    std::string data_path  = argv[4];
    int         nbits      = std::atoi(argv[5]);
    int         es         = std::atoi(argv[6]);
    std::string source     = argv[7];
    std::string out_csv    = argv[8];

    std::printf("model=%s  posit<%d,%d>  source=%s  dtype=%s  format=%s\n",
                model_name.c_str(), nbits, es, source.c_str(), dtype.c_str(), POSIT_FORMAT);
    std::fflush(stdout);

    std::pair<float, float> result;

    if (dtype == "posit") {
        if (model_name == "resnet18")
            result = dispatch_native_cifar<ResNet18Posit>(nbits, es, ckpt, data_path);
        else if (model_name == "cifarnet")
            result = dispatch_native_cifar<CifarNetPosit>(nbits, es, ckpt, data_path);
        else if (model_name == "smallnet")
            result = dispatch_native_mnist<SmallNetPosit>(nbits, es, ckpt, data_path);
        else {
            std::fprintf(stderr, "ERROR: unknown model '%s'\n", model_name.c_str());
            return 1;
        }
    } else {
        bool use_double = (dtype == "double");
        if (model_name == "resnet18") {
            result = use_double
                ? dispatch_cifar<double, ResNet18Posit>(nbits, es, ckpt, data_path)
                : dispatch_cifar<float,  ResNet18Posit>(nbits, es, ckpt, data_path);
        } else if (model_name == "cifarnet") {
            result = use_double
                ? dispatch_cifar<double, CifarNetPosit>(nbits, es, ckpt, data_path)
                : dispatch_cifar<float,  CifarNetPosit>(nbits, es, ckpt, data_path);
        } else if (model_name == "smallnet") {
            result = use_double
                ? dispatch_mnist<double, SmallNetPosit>(nbits, es, ckpt, data_path)
                : dispatch_mnist<float,  SmallNetPosit>(nbits, es, ckpt, data_path);
        } else {
            std::fprintf(stderr, "ERROR: unknown model '%s'\n", model_name.c_str());
            return 1;
        }
    }

    auto [acc, nll] = result;
    std::printf("  -> acc=%.4f  nll=%.4f\n", acc, nll);

    bool write_header = !std::ifstream(out_csv).good();
    std::ofstream csv(out_csv, std::ios::app);
    if (write_header)
        csv << "source,format,nbits,es,val_acc,val_nll\n";
    csv << source << "," << POSIT_FORMAT << ","
        << nbits << "," << es << "," << acc << "," << nll << "\n";

    return 0;
}
