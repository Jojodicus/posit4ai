#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL=smallnet
DATA=dataset/mnist
CKPT_DIR=results/smallnet/checkpoints
LOG_DIR=results/smallnet/logs
CKPT_FP32_JIT=$CKPT_DIR/ckpt_smallnet_jit.pt
INF_CSV=$LOG_DIR/inference_results.csv

mkdir -p "$LOG_DIR"

echo "=== SmallNet: build C++ with quire ==="
cmake -S cpp -B cpp/build_quire -DQUIRE_MODE=2 -DCMAKE_BUILD_TYPE=Release -Wno-dev
cmake --build cpp/build_quire -j"$(nproc)"

echo "=== SmallNet: posit inference sweep (quire, from fp32) ==="
for NBITS in 10 12 14; do
    for ES in 1 2 3; do
        echo "  p${NBITS}e${ES} (quire)"
        cpp/build_quire/inference_posit \
            $MODEL $CKPT_FP32_JIT float $DATA $NBITS $ES \
            smallnet_fp32 $INF_CSV
    done
done

echo "=== SmallNet: build C++ without quire ==="
cmake -S cpp -B cpp/build_noquire -DQUIRE_MODE=0 -DCMAKE_BUILD_TYPE=Release -Wno-dev
cmake --build cpp/build_noquire -j"$(nproc)"

echo "=== SmallNet: posit inference sweep (no quire, from fp32) ==="
for NBITS in 10 12 14; do
    for ES in 1 2 3; do
        echo "  p${NBITS}e${ES} (no quire)"
        cpp/build_noquire/inference_posit \
            $MODEL $CKPT_FP32_JIT float $DATA $NBITS $ES \
            smallnet_fp32 $INF_CSV
    done
done

echo "=== SmallNet: done ==="
