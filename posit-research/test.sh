#!/bin/bash
# Test Script: Run All Testbenches
# Usage: ./test.sh

set -e

# Navigate to project root
cd "$(dirname "$0")"

# Source Vivado environment
source scripts/vivado_env.sh

echo "========================================"
echo "Running All Testbenches"
echo "========================================"
echo "Simulations (accel_core — all configs):"
echo "  sim_pau8         — PAU  8-bit (FloPoCo, es=2)"
echo "  sim_pau16        — PAU 16-bit (FloPoCo, es=2)"
echo "  sim_pau32        — PAU 32-bit exact"
echo "  sim_pau32_approx — PAU 32-bit approx-mul"
echo "  sim_pau64        — PAU 64-bit exact"
echo "  sim_fpu32        — FPU 32-bit (IEEE 754 single)"
echo "  sim_fpu64        — FPU 64-bit (IEEE 754 double)"
echo "Simulations (AXI integration):"
echo "  sim_axi          — tb_accel_axi PAU-32  (32-bit DBRAM path, STATUS polling)"
echo "  sim_axi_pau64    — tb_accel_axi PAU-64  (64-bit DBRAM_DATA_HI path)"
echo "========================================"
echo ""

# Ensure project exists
ensure_project

# Run all tests
run_vivado_batch scripts/run_all_tests.tcl

echo ""
echo "========================================"
echo "All Tests Complete!"
echo "========================================"
echo "Check Vivado output above for results."
echo ""
echo "Next steps:"
echo "  - Build design: ./build.sh"
echo "  - Open GUI for debugging: ./open.sh"
echo "========================================"
