#!/bin/bash
# Quick Build Script: Synthesis + Verification

set -e
cd "$(dirname "$0")"
source scripts/vivado_env.sh

CLOCK_FREQ_MHZ="${1:-100}"

echo "========================================"
echo "Quick Build (Synthesis Only)"
echo "Clock Frequency: ${CLOCK_FREQ_MHZ} MHz"
echo "========================================"

export CLOCK_FREQ_MHZ

mkdir -p reports
run_vivado_batch scripts/run_build.tcl

echo ""
echo "========================================"
echo "Build Complete! Reports available in: reports/"
echo "========================================"
