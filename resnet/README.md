# Posit Accuracy Frontier — ResNet-18 & CifarNet on CIFAR-10

Experiments comparing posit and float number formats for neural network inference accuracy.

## Setup

```bash
uv sync
./init.sh
```

For posit inference, also build the C++ binary. Requires LibTorch (bundled in the submodule):

```bash
cmake -S cpp -B cpp/build -DCMAKE_BUILD_TYPE=Release
cmake --build cpp/build -j$(nproc)
```

## ResNet-18

**Train (FP32):**
```bash
uv run python src/train_resnet.py
```

**Fine-tune in FP64:**
```bash
uv run python src/finetune_resnet.py
```

**Float-format inference (FP16/BF16/TF32):**
```bash
uv run python src/inference_float.py --model resnet18 \
    --ckpt results/checkpoints/ckpt_resnet18.pt --source resnet18_fp32

uv run python src/inference_float.py --model resnet18 \
    --ckpt results/checkpoints/ckpt_resnet18_fp64_ft.pt --source resnet18_fp64_ft \
    --ckpt-dtype float64
```

**Posit inference (from float checkpoint):**
```bash
cpp/build/inference_posit resnet18 \
    results/checkpoints/ckpt_resnet18_fused.pt float dataset/cifar10/ \
    8 2 resnet18_fp32 results/logs/inference_results.csv
```

**Posit train from scratch (D1):**
```bash
cpp/build/train_posit resnet18 dataset/cifar10/ \
    8 2 results/checkpoints/ckpt_resnet18_p8es2.dat \
    resnet18_p8es2_scratch results/logs/train_p8es2_scratch.csv
```

**Posit fine-tune from float checkpoint (D2):**
```bash
cpp/build/finetune_posit resnet18 \
    results/checkpoints/ckpt_resnet18_fused.pt float dataset/cifar10/ \
    8 2 20 results/checkpoints/ckpt_resnet18_p8es2_ft.dat \
    resnet18_p8es2_ft results/logs/train_p8es2_ft.csv
```

**Posit inference from posit-native checkpoint:**
```bash
cpp/build/inference_posit resnet18 \
    results/checkpoints/ckpt_resnet18_p8es2.dat posit dataset/cifar10/ \
    8 2 resnet18_p8es2_scratch results/logs/inference_results.csv
```

## CifarNet

**Train (FP32):**
```bash
uv run python src/train_cifarnet.py
```

**Fine-tune in FP64:**
```bash
uv run python src/finetune_cifarnet.py
```

**Float-format inference (FP16/BF16/TF32/...):**
```bash
uv run python src/inference_float.py --model cifarnet \
    --ckpt results/checkpoints/ckpt_cifarnet.pt --source cifarnet_fp32

uv run python src/inference_float.py --model cifarnet \
    --ckpt results/checkpoints/ckpt_cifarnet_fp64_ft.pt --source cifarnet_fp64_ft \
    --ckpt-dtype float64
```

**Posit inference (from float checkpoint):**
```bash
cpp/build/inference_posit cifarnet \
    results/checkpoints/ckpt_cifarnet_jit.pt float dataset/cifar10/ \
    8 2 cifarnet_fp32 results/logs/inference_results.csv
```

**Posit train from scratch (D1):**
```bash
cpp/build/train_posit cifarnet dataset/cifar10/ \
    8 2 results/checkpoints/ckpt_cifarnet_p8es2.dat \
    cifarnet_p8es2_scratch results/logs/train_p8es2_scratch.csv
```

**Posit fine-tune from float checkpoint (D2):**
```bash
cpp/build/finetune_posit cifarnet \
    results/checkpoints/ckpt_cifarnet_jit.pt float dataset/cifar10/ \
    8 2 20 results/checkpoints/ckpt_cifarnet_p8es2_ft.dat \
    cifarnet_p8es2_ft results/logs/train_p8es2_ft.csv
```

**Posit inference from posit-native checkpoint:**
```bash
cpp/build/inference_posit cifarnet \
    results/checkpoints/ckpt_cifarnet_p8es2.dat posit dataset/cifar10/ \
    8 2 cifarnet_p8es2_scratch results/logs/inference_results.csv
```

## Quire mode

The `QUIRE_MODE` CMake definition controls posit accumulation. Rebuild with a different value to change it:

```bash
cmake -S cpp -B cpp/build -DCMAKE_BUILD_TYPE=Release
# Edit cpp/CMakeLists.txt: set QUIRE_MODE to 0 (disabled), 1, or 2
cmake --build cpp/build -j$(nproc)
```

When `QUIRE_MODE != 0`, the format column in `inference_results.csv` is written as `positQ` instead of `posit`.

## Plotting

```bash
uv run python scripts/plot.py
```

## Output

Per-epoch logs: `results/logs/<run>.csv` — epoch, train_loss, val_acc, val_nll, lr

Inference sweep: `results/logs/inference_results.csv` — source, model, format, nbits, es, val_acc, val_nll

- `format` is `posit` or `positQ` (quire enabled), `fp16`, `bf16`, or `tf32`
