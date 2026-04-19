#!/bin/bash
# Test Script: Run All Testbenches

set -e
cd "$(dirname "$0")"
source scripts/vivado_env.sh

echo "========================================"
echo "Running All Testbenches"
echo "========================================"
echo ""

ensure_project

run_vivado_batch scripts/run_all_tests.tcl

echo ""
echo "========================================"
echo "All Tests Complete!"
echo "========================================"
