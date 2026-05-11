# Posit Accuracy Frontier - ResNet-18, CifarNet & SmallNet

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
    --ckpt results/resnet/checkpoints/ckpt_resnet18.pt --source resnet18_fp32

uv run python src/inference_float.py --model resnet18 \
    --ckpt results/resnet/checkpoints/ckpt_resnet18_fp64_ft.pt --source resnet18_fp64_ft \
    --ckpt-dtype float64
```

**Posit inference (from float checkpoint):**
```bash
cpp/build/inference_posit resnet18 \
    results/resnet/checkpoints/ckpt_resnet18_fused.pt float dataset/cifar10/ \
    8 2 resnet18_fp32 results/resnet/logs/inference_results.csv
```

**Posit train from scratch:**
```bash
cpp/build/train_posit resnet18 dataset/cifar10/ \
    8 2 results/resnet/checkpoints/ckpt_resnet18_p8es2.dat \
    resnet18_p8es2_scratch results/resnet/logs/train_p8es2_scratch.csv
```

**Posit fine-tune from float checkpoint:**
```bash
cpp/build/finetune_posit resnet18 \
    results/resnet/checkpoints/ckpt_resnet18_fused.pt float dataset/cifar10/ \
    8 2 20 results/resnet/checkpoints/ckpt_resnet18_p8es2_ft.dat \
    resnet18_p8es2_ft results/resnet/logs/train_p8es2_ft.csv
```

**Posit inference from posit-native checkpoint:**
```bash
cpp/build/inference_posit resnet18 \
    results/resnet/checkpoints/ckpt_resnet18_p8es2.dat posit dataset/cifar10/ \
    8 2 resnet18_p8es2_scratch results/resnet/logs/inference_results.csv
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
    --ckpt results/cifarnet/checkpoints/ckpt_cifarnet.pt --source cifarnet_fp32

uv run python src/inference_float.py --model cifarnet \
    --ckpt results/cifarnet/checkpoints/ckpt_cifarnet_fp64_ft.pt --source cifarnet_fp64_ft \
    --ckpt-dtype float64
```

**Posit inference (from float checkpoint):**
```bash
cpp/build/inference_posit cifarnet \
    results/cifarnet/checkpoints/ckpt_cifarnet_jit.pt float dataset/cifar10/ \
    8 2 cifarnet_fp32 results/cifarnet/logs/inference_results.csv
```

**Posit train from scratch:**
```bash
cpp/build/train_posit cifarnet dataset/cifar10/ \
    8 2 results/cifarnet/checkpoints/ckpt_cifarnet_p8es2.dat \
    cifarnet_p8es2_scratch results/cifarnet/logs/train_p8es2_scratch.csv
```

**Posit fine-tune from float checkpoint:**
```bash
cpp/build/finetune_posit cifarnet \
    results/cifarnet/checkpoints/ckpt_cifarnet_jit.pt float dataset/cifar10/ \
    8 2 10 results/cifarnet/checkpoints/ckpt_cifarnet_p8es2_ft.dat \
    cifarnet_p8es2_ft results/cifarnet/logs/train_p8es2_ft.csv
```

**Posit inference from posit-native checkpoint:**
```bash
cpp/build/inference_posit cifarnet \
    results/cifarnet/checkpoints/ckpt_cifarnet_p8es2.dat posit dataset/cifar10/ \
    8 2 cifarnet_p8es2_scratch results/cifarnet/logs/inference_results.csv
```

## SmallNet

One hidden layer FC network (784->32->10) trained on MNIST.

**Train (FP32):**
```bash
uv run python src/train_smallnet.py
```

**Fine-tune in FP64:**
```bash
uv run python src/finetune_smallnet.py
```

**Float-format inference (FP16/BF16/TF32/...):**
```bash
uv run python src/inference_float.py --model smallnet \
    --ckpt results/smallnet/checkpoints/ckpt_smallnet.pt --source smallnet_fp32

uv run python src/inference_float.py --model smallnet \
    --ckpt results/smallnet/checkpoints/ckpt_smallnet_fp64_ft.pt --source smallnet_fp64_ft \
    --ckpt-dtype float64
```

**Posit inference (from float checkpoint):**
```bash
cpp/build/inference_posit smallnet \
    results/smallnet/checkpoints/ckpt_smallnet_jit.pt float dataset/mnist/ \
    8 2 smallnet_fp32 results/smallnet/logs/inference_results.csv
```

**Posit train from scratch:**
```bash
cpp/build/train_posit smallnet dataset/mnist/ \
    8 2 results/smallnet/checkpoints/ckpt_smallnet_p8es2.dat \
    smallnet_p8es2_scratch results/smallnet/logs/train_p8es2_scratch.csv
```

**Posit fine-tune from float checkpoint:**
```bash
cpp/build/finetune_posit smallnet \
    results/smallnet/checkpoints/ckpt_smallnet_jit.pt float dataset/mnist/ \
    8 2 10 results/smallnet/checkpoints/ckpt_smallnet_p8es2_ft.dat \
    smallnet_p8es2_ft results/smallnet/logs/train_p8es2_ft.csv
```

**Posit inference from posit-native checkpoint:**
```bash
cpp/build/inference_posit smallnet \
    results/smallnet/checkpoints/ckpt_smallnet_p8es2.dat posit dataset/mnist/ \
    8 2 smallnet_p8es2_scratch results/smallnet/logs/inference_results.csv
```

## Quire mode

Pass `-DQUIRE_MODE=<value>` to cmake at configure time. Values: `0` = disabled,
`1` = old standard, `2` = new standard (default).

```bash
cmake -S cpp -B cpp/build -DCMAKE_BUILD_TYPE=Release -DQUIRE_MODE=0
cmake --build cpp/build -j$(nproc)
```

When `QUIRE_MODE != 0`, the format column in `inference_results.csv` is written as `positQ` instead of `posit`.

## Plotting

```bash
uv run python scripts/plot.py
```

## Output

Results are organized per model under `results/<model>/`

Per-epoch logs: `results/<model>/logs/<run>.csv` - epoch, train_loss, train_acc, val_acc, val_nll, lr

Inference sweep: `results/<model>/logs/inference_results.csv` - source, format, nbits, es, val_acc, val_nll

- `source` is the checkpoint label (e.g. `resnet18_fp32`, `cifarnet_fp64_ft`)
- `format` is `posit` or `positQ` (quire enabled), `fp16`, `bf16`, `tf32`, `fp32`, or `fp64`
