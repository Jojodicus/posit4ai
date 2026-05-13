#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL=resnet18
DATA=dataset/cifar10
CKPT_DIR=results/resnet/checkpoints
LOG_DIR=results/resnet/logs
CKPT_FP32_JIT=$CKPT_DIR/ckpt_resnet18_fused.pt
CKPT_FP32_PY=$CKPT_DIR/ckpt_resnet18.pt
CKPT_FP64_PY=$CKPT_DIR/ckpt_resnet18_fp64_ft.pt
CKPT_P32E2=$CKPT_DIR/ckpt_resnet18_p32e2_ft.dat
INF_CSV=$LOG_DIR/inference_results.csv

echo "=== ResNet: train FP32 ==="
uv run python src/train_resnet.py

echo "=== ResNet: finetune FP64 ==="
uv run python src/finetune_resnet.py

echo "=== ResNet: float inference on ckpt_fp32 ==="
uv run python src/inference_float.py \
    --model $MODEL --ckpt $CKPT_FP32_PY --ckpt-dtype float32 \
    --source resnet18_fp32 --formats fp16 bf16 tf32 fp32

echo "=== ResNet: float inference on ckpt_fp64_ft ==="
uv run python src/inference_float.py \
    --model $MODEL --ckpt $CKPT_FP64_PY --ckpt-dtype float64 \
    --source resnet18_fp64_ft --formats fp16 bf16 tf32 fp32 fp64

echo "=== ResNet: build C++ with quire ==="
cmake -S cpp -B cpp/build_quire -DQUIRE_MODE=2 -DCMAKE_BUILD_TYPE=Release -Wno-dev
cmake --build cpp/build_quire -j"$(nproc)"

echo "=== ResNet: posit inference sweep (quire, from fp32) ==="
for NBITS in 8 16 32; do
    for ES in 1 2 3; do
        echo "  p${NBITS}e${ES} (quire)"
        cpp/build_quire/inference_posit \
            $MODEL $CKPT_FP32_JIT float $DATA $NBITS $ES \
            resnet18_fp32 $INF_CSV
    done
done

echo "=== ResNet: posit finetune p32e2 (quire) ==="
cpp/build_quire/finetune_posit \
    $MODEL $CKPT_FP32_JIT float $DATA 32 2 10 \
    $CKPT_P32E2 resnet18_p32e2_ft $LOG_DIR/finetune_p32e2.csv

echo "=== ResNet: posit inference p32e2_ft (quire) ==="
cpp/build_quire/inference_posit \
    $MODEL $CKPT_P32E2 posit $DATA 32 2 \
    resnet18_p32e2_ft $INF_CSV

echo "=== ResNet: build C++ without quire ==="
cmake -S cpp -B cpp/build_noquire -DQUIRE_MODE=0 -DCMAKE_BUILD_TYPE=Release -Wno-dev
cmake --build cpp/build_noquire -j"$(nproc)"

echo "=== ResNet: posit inference sweep (no quire, from fp32) ==="
for NBITS in 8 16 32; do
    for ES in 1 2 3; do
        echo "  p${NBITS}e${ES} (no quire)"
        cpp/build_noquire/inference_posit \
            $MODEL $CKPT_FP32_JIT float $DATA $NBITS $ES \
            resnet18_fp32 $INF_CSV
    done
done

echo "=== ResNet: posit inference p32e2_ft (no quire) ==="
cpp/build_noquire/inference_posit \
    $MODEL $CKPT_P32E2 posit $DATA 32 2 \
    resnet18_p32e2_ft $INF_CSV

echo "=== ResNet: done ==="
