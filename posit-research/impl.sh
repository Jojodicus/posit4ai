#!/bin/bash
# Full Implementation Script: Synthesis + Place & Route + Bitstream
# Usage: ./impl.sh [FREQ_MHZ]
# Default: 100 MHz

set -e

# Navigate to project root
cd "$(dirname "$0")"

# Source Vivado environment
source scripts/vivado_env.sh

# Get clock frequency from argument (default: 100 MHz)
CLOCK_FREQ_MHZ="${1:-100}"

echo "========================================"
echo "Full FPGA Implementation"
echo "Clock Frequency: ${CLOCK_FREQ_MHZ} MHz"
echo "Target: zynq_pau_top (PS7 + pau_fpu_harness_axi)"
echo "========================================"
echo ""
echo "This will take several minutes..."
echo ""

# Export clock frequency for TCL script
export CLOCK_FREQ_MHZ

# Create reports directory
mkdir -p reports

# Run full implementation
run_vivado_batch scripts/run_impl.tcl

echo ""
echo "========================================"
echo "Implementation Complete!"
echo "========================================"
echo "Bitstream: vivado_proj/posit_research.runs/impl_1/zynq_pau_top.bit"
echo ""
echo "Reports available in: reports/"
echo "- reports/timing_summary.rpt"
echo "- reports/timing_detailed.rpt"
echo "- reports/utilization.rpt"
echo "- reports/utilization_hierarchical.rpt"
echo "- reports/power.rpt"
echo "- reports/clock_networks.rpt"
echo ""
echo "Next steps:"
echo "  - Inspect results: ./open.sh"
echo "  - Review timing: cat reports/timing_summary.rpt"
echo "========================================"
