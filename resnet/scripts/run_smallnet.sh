#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL=smallnet
DATA=dataset/mnist
CKPT_DIR=results/smallnet/checkpoints
LOG_DIR=results/smallnet/logs
CKPT_FP32_JIT=$CKPT_DIR/ckpt_smallnet_jit.pt
CKPT_FP32_PY=$CKPT_DIR/ckpt_smallnet.pt
CKPT_FP64_PY=$CKPT_DIR/ckpt_smallnet_fp64_ft_jit.pt
CKPT_P8E2=$CKPT_DIR/ckpt_smallnet_p8e2_ft.dat
INF_CSV=$LOG_DIR/inference_results.csv

echo "=== SmallNet: train FP32 ==="
uv run python src/train_smallnet.py

echo "=== SmallNet: finetune FP64 ==="
uv run python src/finetune_smallnet.py

echo "=== SmallNet: float inference on ckpt_fp32 ==="
uv run python src/inference_float.py \
    --model $MODEL --ckpt $CKPT_FP32_PY --ckpt-dtype float32 \
    --source smallnet_fp32 --formats fp16 bf16 tf32 fp32

echo "=== SmallNet: float inference on ckpt_fp64_ft ==="
uv run python src/inference_float.py \
    --model $MODEL --ckpt $CKPT_FP64_PY --ckpt-dtype float64 \
    --source smallnet_fp64_ft --formats fp16 bf16 tf32 fp32 fp64

echo "=== SmallNet: build C++ with quire ==="
cmake -S cpp -B cpp/build_quire -DQUIRE_MODE=2 -DCMAKE_BUILD_TYPE=Release -Wno-dev
cmake --build cpp/build_quire -j"$(nproc)"

echo "=== SmallNet: posit inference sweep (quire, from fp32) ==="
for NBITS in 8 16 32; do
    for ES in 1 2 3; do
        echo "  p${NBITS}e${ES} (quire)"
        cpp/build_quire/inference_posit \
            $MODEL $CKPT_FP32_JIT float $DATA $NBITS $ES \
            smallnet_fp32 $INF_CSV
    done
done

echo "=== SmallNet: posit finetune p8e2 (quire) ==="
cpp/build_quire/finetune_posit \
    $MODEL $CKPT_FP32_JIT float $DATA 8 2 10 \
    $CKPT_P8E2 smallnet_p8e2_ft $LOG_DIR/finetune_p8e2.csv

echo "=== SmallNet: posit inference p8e2_ft (quire) ==="
cpp/build_quire/inference_posit \
    $MODEL $CKPT_P8E2 posit $DATA 8 2 \
    smallnet_p8e2_ft $INF_CSV

echo "=== SmallNet: posit from-scratch training (quire) ==="
for CFG in "32 2" "32 1" "16 2" "16 1" "8 2"; do
    NBITS=$(echo $CFG | cut -d' ' -f1)
    ES=$(echo $CFG | cut -d' ' -f2)
    SCRATCH_CKPT=$CKPT_DIR/ckpt_smallnet_p${NBITS}e${ES}_scratch.dat
    echo "  train p${NBITS}e${ES} from scratch"
    cpp/build_quire/train_posit \
        $MODEL $DATA $NBITS $ES \
        $SCRATCH_CKPT \
        smallnet_p${NBITS}e${ES}_scratch \
        $LOG_DIR/train_p${NBITS}e${ES}_scratch.csv
    echo "  inference p${NBITS}e${ES} scratch (quire)"
    cpp/build_quire/inference_posit \
        $MODEL $SCRATCH_CKPT posit $DATA $NBITS $ES \
        smallnet_p${NBITS}e${ES}_scratch $INF_CSV
done

echo "=== SmallNet: build C++ without quire ==="
cmake -S cpp -B cpp/build_noquire -DQUIRE_MODE=0 -DCMAKE_BUILD_TYPE=Release -Wno-dev
cmake --build cpp/build_noquire -j"$(nproc)"

echo "=== SmallNet: posit inference sweep (no quire, from fp32) ==="
for NBITS in 8 16 32; do
    for ES in 1 2 3; do
        echo "  p${NBITS}e${ES} (no quire)"
        cpp/build_noquire/inference_posit \
            $MODEL $CKPT_FP32_JIT float $DATA $NBITS $ES \
            smallnet_fp32 $INF_CSV
    done
done

echo "=== SmallNet: posit inference p8e2_ft (no quire) ==="
cpp/build_noquire/inference_posit \
    $MODEL $CKPT_P8E2 posit $DATA 8 2 \
    smallnet_p8e2_ft $INF_CSV

echo "=== SmallNet: posit inference scratch models (no quire) ==="
for CFG in "32 2" "32 1" "16 2" "16 1" "8 2"; do
    NBITS=$(echo $CFG | cut -d' ' -f1)
    ES=$(echo $CFG | cut -d' ' -f2)
    SCRATCH_CKPT=$CKPT_DIR/ckpt_smallnet_p${NBITS}e${ES}_scratch.dat
    echo "  p${NBITS}e${ES} scratch (no quire)"
    cpp/build_noquire/inference_posit \
        $MODEL $SCRATCH_CKPT posit $DATA $NBITS $ES \
        smallnet_p${NBITS}e${ES}_scratch $INF_CSV
done

echo "=== SmallNet: done ==="
