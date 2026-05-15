#!/bin/bash
# bench_all.sh -- run all EMULSION benchmarks for a given posit width.
#
# Usage:  ./bench_all.sh <specifier>
#   specifier:  emu8 | emu16 | emu32
#
# Runs both quire and no-quire modes for GEMM and CONV.
# Output: results/<specifier>/logs/*.log + results/<specifier>/results.csv

set -e

SPEC="$1"
if [ -z "$SPEC" ]; then
    echo "Usage: $0 <emu8|emu16|emu32>"
    exit 1
fi

DIR=$(cd "$(dirname "$0")" && pwd)
RESDIR="$DIR/results/${SPEC}"
LOGDIR="$RESDIR/logs"

mkdir -p "$LOGDIR"

echo "=== EMULSION benchmarks: ${SPEC} ==="
echo "  logs -> ${LOGDIR}/"
echo "  csv  -> ${RESDIR}/"

cd "$DIR"

# ---- Per-op throughput ----
echo "--- Per-op throughput (${SPEC}) ---"
"./bench_per_op.${SPEC}.elf" > "$LOGDIR/per_op_${SPEC}.log" 2>&1

# ---- GEMM: quire mode ----
for S in 32 64 128 256; do
    echo "--- GEMM ${S}x${S}x${S} (${SPEC}, quire) ---"
    "./bench_gemm.${SPEC}.elf" "$S" "$S" "$S" \
        > "$LOGDIR/gemm_${S}_${SPEC}_quire.log" 2>&1
done

# ---- GEMM: no-quire mode ----
for S in 32 64 128 256; do
    echo "--- GEMM ${S}x${S}x${S} (${SPEC}, no-quire) ---"
    "./bench_gemm.${SPEC}.elf" "$S" "$S" "$S" --no-quire \
        > "$LOGDIR/gemm_${S}_${SPEC}_noquire.log" 2>&1
done

# ---- CONV 3x3 ----
for IMG in 16 32 64; do
    echo "--- CONV ${IMG}x${IMG} k3x3 (${SPEC}, quire) ---"
    "./bench_conv.${SPEC}.elf" "$IMG" "$IMG" 3 3 \
        > "$LOGDIR/conv_${IMG}x${IMG}_k3_${SPEC}_quire.log" 2>&1
    echo "--- CONV ${IMG}x${IMG} k3x3 (${SPEC}, no-quire) ---"
    "./bench_conv.${SPEC}.elf" "$IMG" "$IMG" 3 3 --no-quire \
        > "$LOGDIR/conv_${IMG}x${IMG}_k3_${SPEC}_noquire.log" 2>&1
done

# ---- CONV 5x5 ----
for IMG in 32 64; do
    echo "--- CONV ${IMG}x${IMG} k5x5 (${SPEC}, quire) ---"
    "./bench_conv.${SPEC}.elf" "$IMG" "$IMG" 5 5 \
        > "$LOGDIR/conv_${IMG}x${IMG}_k5_${SPEC}_quire.log" 2>&1
    echo "--- CONV ${IMG}x${IMG} k5x5 (${SPEC}, no-quire) ---"
    "./bench_conv.${SPEC}.elf" "$IMG" "$IMG" 5 5 --no-quire \
        > "$LOGDIR/conv_${IMG}x${IMG}_k5_${SPEC}_noquire.log" 2>&1
done

# ---- Collect CSV ----
echo "=== Collecting results ==="
{
    echo "# Results: EMULSION ${SPEC}"
    echo "# Columns: benchmark_type,<type-specific-fields>...,config"
    grep -h '^#CSV,' "$LOGDIR"/*.log \
        | sed "s/\$/,${SPEC}/"
} > "$RESDIR/results.csv"

echo "=== Done ==="
echo "Results: ${RESDIR}/results.csv"
