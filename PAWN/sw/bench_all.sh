#!/bin/bash
# bench_all.sh -- run all PAWN benchmarks for a given bitstream config.
#
# Usage:  ./bench_all.sh <bitstream_path> <mode> <data_width>
#
#   bitstream_path  path to .bin file (basename used as CSV config tag)
#   mode            "quire" or "no-quire"
#   data_width      "32" or "64"

set -e

BITSTREAM="$1"
MODE="$2"
DW="$3"

if [ -z "$BITSTREAM" ] || [ -z "$MODE" ] || [ -z "$DW" ]; then
    echo "Usage: $0 <bitstream_path> <mode=quire|no-quire> <data_width=32|64>"
    exit 1
fi

BSNAME=$(basename "$BITSTREAM" .bin)
DIR=$(cd "$(dirname "$0")" && pwd)
RESDIR="$DIR/results/${BSNAME}"
LOGDIR="$RESDIR/logs"

mkdir -p "$LOGDIR"

SUFFIX="" && [ "$DW" = "64" ] && SUFFIX="64"
NOQUIRE="" && [ "$MODE" = "no-quire" ] && NOQUIRE="--no-quire"

# ---- Load bitstream ----
echo "=== Loading bitstream: ${BSNAME} ==="
cp "$BITSTREAM" /lib/firmware/
"$DIR/load.sh" "${BSNAME}.bin"

cd "$DIR"

echo "=== PAWN benchmarks: ${BSNAME}  mode=${MODE}  ${DW}-bit ==="
echo "  logs -> ${LOGDIR}/"
echo "  csv  -> ${RESDIR}/"

# ---- Per-op throughput ----
echo "--- Per-op throughput (${DW}-bit, ${MODE}) ---"
./pawn/examples/bench_per_op${SUFFIX}.elf > "$LOGDIR/per_op_${BSNAME}_${MODE}.log" 2>&1

# ---- GEMM: M=N=K = 32, 64, 128, 256 ----
for S in 32 64 128 256; do
    echo "--- GEMM ${S}x${S}x${S} (${DW}-bit, ${MODE}) ---"
    ./pawn/examples/bench_gemm${SUFFIX}.elf "$S" "$S" "$S" $NOQUIRE \
        > "$LOGDIR/gemm_${S}_${BSNAME}_${MODE}.log" 2>&1
done

# ---- CONV: 3x3 kernel ----
for IMG in 16 32 64; do
    echo "--- CONV ${IMG}x${IMG} k3x3 (${DW}-bit, ${MODE}) ---"
    ./pawn/examples/bench_conv${SUFFIX}.elf "$IMG" "$IMG" 3 3 $NOQUIRE \
        > "$LOGDIR/conv_${IMG}x${IMG}_k3_${BSNAME}_${MODE}.log" 2>&1
done

# ---- CONV: 5x5 kernel ----
for IMG in 32 64; do
    echo "--- CONV ${IMG}x${IMG} k5x5 (${DW}-bit, ${MODE}) ---"
    ./pawn/examples/bench_conv${SUFFIX}.elf "$IMG" "$IMG" 5 5 $NOQUIRE \
        > "$LOGDIR/conv_${IMG}x${IMG}_k5_${BSNAME}_${MODE}.log" 2>&1
done

# ---- Collect CSV ----
echo "=== Collecting results ==="
{
    echo "# Results: ${BSNAME}  mode=${MODE}  ${DW}-bit"
    echo "# Columns: benchmark_type,<type-specific-fields>...,config"
    grep -h '^#CSV,' "$LOGDIR"/*.log \
        | sed "s/\$/,${BSNAME}/"
} > "$RESDIR/results_${MODE}.csv"

echo "=== Done ==="
echo "Results: ${RESDIR}/results_${MODE}.csv"
