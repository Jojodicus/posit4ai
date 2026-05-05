// Posit from-scratch training (Phase 4 / D1).
//
// Usage:
//   ./train_posit <model:resnet18|cifarnet> <cifar10_dir>
//                 <nbits> <es> <out_ckpt.dat> <run_name> <out_csv>
//
// Trains for 200 epochs with cosine LR (0.1->0), SGD momentum=0.9,
// weight_decay=5e-4, batch=128. Logs CSV: epoch,train_loss,val_acc,val_nll,lr.

#include <cstdio>
#include <fstream>
#include <iostream>
#include <string>

#include <torch/torch.h>
#include <universal/posit/posit>
#include <positnn/positnn>

#include "Cifar10Data.hpp"
#include "posit_types.hpp"
#include "posit_train_utils.hpp"
#include "resnet18.hpp"
#include "cifarnet.hpp"

static const size_t NUM_EPOCHS  = 200;
static const size_t BATCH_SIZE  = 128;
static const float  LR_MAX      = 0.1f;
static const float  MOMENTUM    = 0.9f;
static const float  WEIGHT_DECAY = 5e-4f;

template<size_t N, size_t E, template<typename> class ModelT>
void run_training(
    const std::string& data_path,
    const std::string& out_ckpt,
    const std::string& run_name,
    const std::string& out_csv
) {
    using PT = PType<N, E>;
    using O  = typename PT::Optimizer;

    torch::manual_seed(42);

    ModelT<PT> model;

    auto train_dataset = Cifar10Data(data_path, true)
        .map(torch::data::transforms::Normalize<>(
            {TRAIN_CIFAR_MEAN[0], TRAIN_CIFAR_MEAN[1], TRAIN_CIFAR_MEAN[2]},
            {TRAIN_CIFAR_STD[0],  TRAIN_CIFAR_STD[1],  TRAIN_CIFAR_STD[2]}))
        .map(torch::data::transforms::Stack<>());

    auto train_loader = torch::data::make_data_loader(
        std::move(train_dataset),
        torch::data::DataLoaderOptions().batch_size(BATCH_SIZE));

    SGD<O> optimizer(model.parameters(),
        SGDOptions<O>(LR_MAX, MOMENTUM, 0.0f, WEIGHT_DECAY));

    bool write_header = !std::ifstream(out_csv).good();
    std::ofstream csv(out_csv, std::ios::app);
    if (write_header)
        csv << "run,epoch,train_loss,val_acc,val_nll,lr\n";

    for (size_t epoch = 1; epoch <= NUM_EPOCHS; epoch++) {
        float lr = LR_MAX * 0.5f * (1.f + std::cos(
            static_cast<float>(M_PI) * float(epoch - 1) / float(NUM_EPOCHS)));

        float train_loss = train_epoch_posit<PT, ModelT>(
            model, *train_loader, optimizer, epoch, NUM_EPOCHS, LR_MAX);

        auto [val_acc, val_nll] = eval_posit<PT, ModelT>(model, data_path);

        std::printf("epoch %3zu/%zu  lr=%.5f  loss=%.4f  val_acc=%.4f  val_nll=%.4f\n",
                    epoch, NUM_EPOCHS, lr, train_loss, val_acc, val_nll);
        std::fflush(stdout);

        csv << run_name << "," << epoch << ","
            << train_loss << "," << val_acc << "," << val_nll << ","
            << lr << "\n";
        csv.flush();
    }

    save<posit<N, E>>(model, out_ckpt);
    std::printf("Saved checkpoint: %s\n", out_ckpt.c_str());
}

template<template<typename> class ModelT>
void dispatch(int nbits, int es,
              const std::string& data, const std::string& ckpt,
              const std::string& run_name, const std::string& out_csv)
{
    if (nbits == 8  && es == 1) { run_training<8,  1, ModelT>(data, ckpt, run_name, out_csv); return; }
    if (nbits == 8  && es == 2) { run_training<8,  2, ModelT>(data, ckpt, run_name, out_csv); return; }
    if (nbits == 8  && es == 3) { run_training<8,  3, ModelT>(data, ckpt, run_name, out_csv); return; }
    if (nbits == 16 && es == 1) { run_training<16, 1, ModelT>(data, ckpt, run_name, out_csv); return; }
    if (nbits == 16 && es == 2) { run_training<16, 2, ModelT>(data, ckpt, run_name, out_csv); return; }
    if (nbits == 16 && es == 3) { run_training<16, 3, ModelT>(data, ckpt, run_name, out_csv); return; }
    if (nbits == 32 && es == 1) { run_training<32, 1, ModelT>(data, ckpt, run_name, out_csv); return; }
    if (nbits == 32 && es == 2) { run_training<32, 2, ModelT>(data, ckpt, run_name, out_csv); return; }
    if (nbits == 32 && es == 3) { run_training<32, 3, ModelT>(data, ckpt, run_name, out_csv); return; }
    std::fprintf(stderr, "ERROR: unsupported nbits=%d es=%d\n", nbits, es);
}

int main(int argc, char* argv[]) {
    if (argc != 8) {
        std::fprintf(stderr,
            "Usage: %s <model:resnet18|cifarnet> <cifar10_dir>"
            " <nbits> <es> <out_ckpt.dat> <run_name> <out_csv>\n",
            argv[0]);
        return 1;
    }

    std::string model_name = argv[1];
    std::string data_path  = argv[2];
    int         nbits      = std::atoi(argv[3]);
    int         es         = std::atoi(argv[4]);
    std::string out_ckpt   = argv[5];
    std::string run_name   = argv[6];
    std::string out_csv    = argv[7];

    std::printf("train_posit  model=%s  posit<%d,%d>  run=%s\n",
                model_name.c_str(), nbits, es, run_name.c_str());
    std::printf("  quire_mode=%d  underflow_mode=%d\n", QUIRE_MODE, UNDERFLOW_MODE);
    std::fflush(stdout);

    if (model_name == "resnet18")
        dispatch<ResNet18Posit>(nbits, es, data_path, out_ckpt, run_name, out_csv);
    else if (model_name == "cifarnet")
        dispatch<CifarNetPosit>(nbits, es, data_path, out_ckpt, run_name, out_csv);
    else {
        std::fprintf(stderr, "ERROR: unknown model '%s'\n", model_name.c_str());
        return 1;
    }

    return 0;
}
