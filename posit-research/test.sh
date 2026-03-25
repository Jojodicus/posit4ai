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
echo "Simulations:"
echo "  sim_core  — tb_accel_core (BRAM + sequencer + arith_unit)"
echo "  sim_axi   — tb_accel_axi  (AXI register interface)"
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
