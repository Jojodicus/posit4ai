#!/bin/bash
# Quick Build Script: Synthesis + Verification
# Usage: ./build.sh [FREQ_MHZ]
# Default: 100 MHz

set -e

# Navigate to project root
cd "$(dirname "$0")"

# Source Vivado environment
source scripts/vivado_env.sh

# Get clock frequency from argument (default: 100 MHz)
CLOCK_FREQ_MHZ="${1:-100}"

echo "========================================"
echo "Quick Build (Synthesis Only)"
echo "Clock Frequency: ${CLOCK_FREQ_MHZ} MHz"
echo "========================================"

# Export clock frequency for TCL script
export CLOCK_FREQ_MHZ

# Create reports directory
mkdir -p reports

# Run synthesis
run_vivado_batch scripts/run_build.tcl

echo ""
echo "========================================"
echo "Build Complete!"
echo "========================================"
echo "Reports available in: reports/"
echo "- reports/build_timing.rpt"
echo "- reports/build_utilization.rpt"
echo ""
echo "Next steps:"
echo "  - Run tests: ./test.sh"
echo "  - Full implementation: ./impl.sh ${CLOCK_FREQ_MHZ}"
echo "  - Open GUI: ./open.sh"
echo "========================================"
