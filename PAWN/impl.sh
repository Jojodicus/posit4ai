#!/bin/bash
# Full Implementation Script: Synthesis + Place & Route + Bitstream

set -e
cd "$(dirname "$0")"
source scripts/vivado_env.sh

CLOCK_FREQ_MHZ="${1:-100}"

echo "========================================"
echo "Full FPGA Implementation"
echo "Clock Frequency: ${CLOCK_FREQ_MHZ} MHz"
echo "========================================"
echo ""
echo "This will take several minutes..."
echo ""

export CLOCK_FREQ_MHZ

mkdir -p reports
run_vivado_batch scripts/run_impl.tcl

echo ""
echo "========================================"
echo "Implementation Complete!"
echo "========================================"
echo "Timing summary: reports/timing_summary.rpt"
echo "To generate the bitstream: ./bit.sh ${CLOCK_FREQ_MHZ}"
echo "========================================"
