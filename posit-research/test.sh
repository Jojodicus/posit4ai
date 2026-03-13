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
echo "This will run:"
echo "  - sim_harness (tb_pau_fpu_harness)"
echo "  - sim_axi (tb_pau_fpu_harness_axi)"
echo "  - sim_pau (tb_pau_top)"
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
