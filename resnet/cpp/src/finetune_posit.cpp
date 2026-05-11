// Posit fine-tune from float checkpoint (Phase 4 / D2).
//
// Usage:
//   ./finetune_posit <model:resnet18|cifarnet|smallnet> <ckpt_float.pt>
//                   <dtype:float|double> <data_dir> <nbits> <es> <num_epochs>
//                   <out_ckpt.dat> <run_name> <out_csv>
//
// For resnet18/cifarnet, data_dir is the CIFAR-10 binary directory.
// For smallnet, data_dir is the MNIST directory (ubyte files).
//
// Loads a TorchScript checkpoint, copies weights to the posit model, then
// fine-tunes with cosine LR (0.01->0), SGD momentum=0.9, weight_decay=5e-4,
// batch=128. Logs CSV: run,epoch,train_loss,train_acc,val_acc,val_nll,lr.

#include <cstdio>
#include <fstream>
#include <iostream>
#include <string>

#include <torch/script.h>
#include <torch/torch.h>
#include <universal/posit/posit>
#include <positnn/positnn>

#include "Cifar10Data.hpp"
#include "posit_types.hpp"
#include "posit_train_utils.hpp"
#include "mnist_train_utils.hpp"
#include "resnet18.hpp"
#include "cifarnet.hpp"
#include "smallnet.hpp"

static const size_t BATCH_SIZE   = 128;
static const float  LR_MAX_FT   = 0.01f;
static const float  MOMENTUM    = 0.9f;
static const float  WEIGHT_DECAY = 5e-4f;

// Fine-tune on CIFAR-10 (resnet18, cifarnet).
template<size_t N, size_t E, typename FromType, template<typename> class ModelT>
void run_finetune(
    const std::string& ckpt_path,
    const std::string& data_path,
    size_t             num_epochs,
    const std::string& out_ckpt,
    const std::string& run_name,
    const std::string& out_csv
) {
    using PT = PType<N, E>;
    using O  = typename PT::Optimizer;

    auto jit_module = torch::jit::load(ckpt_path);
    jit_module.eval();

    std::vector<torch::Tensor> src_params;
    for (const auto& kv : jit_module.named_parameters())
        src_params.push_back(kv.value);

    ModelT<PT> model;

    auto& dst_params = model.parameters();
    if (src_params.size() != dst_params.size()) {
        std::fprintf(stderr,
            "ERROR: parameter count mismatch: JIT=%zu posit=%zu\n",
            src_params.size(), dst_params.size());
        return;
    }
    copy_parameters<FromType>(src_params, dst_params);

    auto train_dataset = Cifar10Data(data_path, true)
        .map(torch::data::transforms::Normalize<>(
            {TRAIN_CIFAR_MEAN[0], TRAIN_CIFAR_MEAN[1], TRAIN_CIFAR_MEAN[2]},
            {TRAIN_CIFAR_STD[0],  TRAIN_CIFAR_STD[1],  TRAIN_CIFAR_STD[2]}))
        .map(torch::data::transforms::Stack<>());

    auto train_loader = torch::data::make_data_loader(
        std::move(train_dataset),
        torch::data::DataLoaderOptions().batch_size(BATCH_SIZE));

    SGD<O> optimizer(model.parameters(),
        SGDOptions<O>(LR_MAX_FT, MOMENTUM, 0.0f, WEIGHT_DECAY));

    bool write_header = !std::ifstream(out_csv).good();
    std::ofstream csv(out_csv, std::ios::app);
    if (write_header)
        csv << "run,epoch,train_loss,train_acc,val_acc,val_nll,lr\n";

    for (size_t epoch = 1; epoch <= num_epochs; epoch++) {
        float lr = LR_MAX_FT * 0.5f * (1.f + std::cos(
            static_cast<float>(M_PI) * float(epoch - 1) / float(num_epochs)));

        auto [train_loss, train_acc] = train_epoch_posit<PT, ModelT>(
            model, *train_loader, optimizer, epoch, num_epochs, LR_MAX_FT);

        auto [val_acc, val_nll] = eval_posit<PT, ModelT>(model, data_path);

        std::printf("epoch %3zu/%zu  lr=%.6f  loss=%.4f  train_acc=%.4f  val_acc=%.4f  val_nll=%.4f\n",
                    epoch, num_epochs, lr, train_loss, train_acc, val_acc, val_nll);
        std::fflush(stdout);

        csv << run_name << "," << epoch << ","
            << train_loss << "," << train_acc << "," << val_acc << "," << val_nll << ","
            << lr << "\n";
        csv.flush();
    }

    save<posit<N, E>>(model, out_ckpt);
    std::printf("Saved checkpoint: %s\n", out_ckpt.c_str());
}

// Fine-tune on MNIST (smallnet).
template<size_t N, size_t E, typename FromType, template<typename> class ModelT>
void run_finetune_mnist(
    const std::string& ckpt_path,
    const std::string& data_path,
    size_t             num_epochs,
    const std::string& out_ckpt,
    const std::string& run_name,
    const std::string& out_csv
) {
    using PT = PType<N, E>;
    using O  = typename PT::Optimizer;

    auto jit_module = torch::jit::load(ckpt_path);
    jit_module.eval();

    std::vector<torch::Tensor> src_params;
    for (const auto& kv : jit_module.named_parameters())
        src_params.push_back(kv.value);

    ModelT<PT> model;

    auto& dst_params = model.parameters();
    if (src_params.size() != dst_params.size()) {
        std::fprintf(stderr,
            "ERROR: parameter count mismatch: JIT=%zu posit=%zu\n",
            src_params.size(), dst_params.size());
        return;
    }
    copy_parameters<FromType>(src_params, dst_params);

    auto train_dataset =
        torch::data::datasets::MNIST(data_path)
        .map(torch::data::transforms::Normalize<>(MNIST_MEAN, MNIST_STD))
        .map(torch::data::transforms::Stack<>());

    auto train_loader = torch::data::make_data_loader(
        std::move(train_dataset),
        torch::data::DataLoaderOptions().batch_size(BATCH_SIZE));

    SGD<O> optimizer(model.parameters(),
        SGDOptions<O>(LR_MAX_FT, MOMENTUM, 0.0f, WEIGHT_DECAY));

    bool write_header = !std::ifstream(out_csv).good();
    std::ofstream csv(out_csv, std::ios::app);
    if (write_header)
        csv << "run,epoch,train_loss,train_acc,val_acc,val_nll,lr\n";

    for (size_t epoch = 1; epoch <= num_epochs; epoch++) {
        float lr = LR_MAX_FT * 0.5f * (1.f + std::cos(
            static_cast<float>(M_PI) * float(epoch - 1) / float(num_epochs)));

        auto [train_loss, train_acc] = train_epoch_posit_mnist<PT, ModelT>(
            model, *train_loader, optimizer, epoch, num_epochs, LR_MAX_FT);

        auto [val_acc, val_nll] = eval_posit_mnist<PT, ModelT>(model, data_path);

        std::printf("epoch %3zu/%zu  lr=%.6f  loss=%.4f  train_acc=%.4f  val_acc=%.4f  val_nll=%.4f\n",
                    epoch, num_epochs, lr, train_loss, train_acc, val_acc, val_nll);
        std::fflush(stdout);

        csv << run_name << "," << epoch << ","
            << train_loss << "," << train_acc << "," << val_acc << "," << val_nll << ","
            << lr << "\n";
        csv.flush();
    }

    save<posit<N, E>>(model, out_ckpt);
    std::printf("Saved checkpoint: %s\n", out_ckpt.c_str());
}

// ---- dispatch tables ----

template<typename FromType, template<typename> class ModelT>
void dispatch_cifar(int nbits, int es,
                    const std::string& ckpt, const std::string& data,
                    size_t num_epochs,
                    const std::string& out_ckpt, const std::string& run_name,
                    const std::string& out_csv)
{
    if (nbits == 8  && es == 1) { run_finetune<8,  1, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 8  && es == 2) { run_finetune<8,  2, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 8  && es == 3) { run_finetune<8,  3, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 16 && es == 1) { run_finetune<16, 1, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 16 && es == 2) { run_finetune<16, 2, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 16 && es == 3) { run_finetune<16, 3, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 32 && es == 1) { run_finetune<32, 1, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 32 && es == 2) { run_finetune<32, 2, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 32 && es == 3) { run_finetune<32, 3, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 64 && es == 1) { run_finetune<64, 1, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 64 && es == 2) { run_finetune<64, 2, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 64 && es == 3) { run_finetune<64, 3, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    std::fprintf(stderr, "ERROR: unsupported nbits=%d es=%d\n", nbits, es);
}

template<typename FromType, template<typename> class ModelT>
void dispatch_mnist(int nbits, int es,
                    const std::string& ckpt, const std::string& data,
                    size_t num_epochs,
                    const std::string& out_ckpt, const std::string& run_name,
                    const std::string& out_csv)
{
    if (nbits == 8  && es == 1) { run_finetune_mnist<8,  1, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 8  && es == 2) { run_finetune_mnist<8,  2, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 8  && es == 3) { run_finetune_mnist<8,  3, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 16 && es == 1) { run_finetune_mnist<16, 1, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 16 && es == 2) { run_finetune_mnist<16, 2, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 16 && es == 3) { run_finetune_mnist<16, 3, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 32 && es == 1) { run_finetune_mnist<32, 1, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 32 && es == 2) { run_finetune_mnist<32, 2, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 32 && es == 3) { run_finetune_mnist<32, 3, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 64 && es == 1) { run_finetune_mnist<64, 1, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 64 && es == 2) { run_finetune_mnist<64, 2, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    if (nbits == 64 && es == 3) { run_finetune_mnist<64, 3, FromType, ModelT>(ckpt, data, num_epochs, out_ckpt, run_name, out_csv); return; }
    std::fprintf(stderr, "ERROR: unsupported nbits=%d es=%d\n", nbits, es);
}

int main(int argc, char* argv[]) {
    if (argc != 11) {
        std::fprintf(stderr,
            "Usage: %s <model:resnet18|cifarnet|smallnet> <ckpt_float.pt>"
            " <dtype:float|double> <data_dir> <nbits> <es> <num_epochs>"
            " <out_ckpt.dat> <run_name> <out_csv>\n",
            argv[0]);
        return 1;
    }

    std::string model_name  = argv[1];
    std::string ckpt        = argv[2];
    std::string dtype       = argv[3];
    std::string data_path   = argv[4];
    int         nbits       = std::atoi(argv[5]);
    int         es          = std::atoi(argv[6]);
    size_t      num_epochs  = static_cast<size_t>(std::atoi(argv[7]));
    std::string out_ckpt    = argv[8];
    std::string run_name    = argv[9];
    std::string out_csv     = argv[10];

    std::printf("finetune_posit  model=%s  posit<%d,%d>  dtype=%s  epochs=%zu  run=%s\n",
                model_name.c_str(), nbits, es, dtype.c_str(), num_epochs, run_name.c_str());
    std::printf("  quire_mode=%d  underflow_mode=%d\n", QUIRE_MODE, UNDERFLOW_MODE);
    std::fflush(stdout);

    bool use_double = (dtype == "double");

    if (model_name == "resnet18") {
        if (use_double)
            dispatch_cifar<double, ResNet18Posit>(nbits, es, ckpt, data_path, num_epochs, out_ckpt, run_name, out_csv);
        else
            dispatch_cifar<float,  ResNet18Posit>(nbits, es, ckpt, data_path, num_epochs, out_ckpt, run_name, out_csv);
    } else if (model_name == "cifarnet") {
        if (use_double)
            dispatch_cifar<double, CifarNetPosit>(nbits, es, ckpt, data_path, num_epochs, out_ckpt, run_name, out_csv);
        else
            dispatch_cifar<float,  CifarNetPosit>(nbits, es, ckpt, data_path, num_epochs, out_ckpt, run_name, out_csv);
    } else if (model_name == "smallnet") {
        if (use_double)
            dispatch_mnist<double, SmallNetPosit>(nbits, es, ckpt, data_path, num_epochs, out_ckpt, run_name, out_csv);
        else
            dispatch_mnist<float,  SmallNetPosit>(nbits, es, ckpt, data_path, num_epochs, out_ckpt, run_name, out_csv);
    } else {
        std::fprintf(stderr, "ERROR: unknown model '%s'\n", model_name.c_str());
        return 1;
    }

    return 0;
}
