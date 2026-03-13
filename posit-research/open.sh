#!/bin/bash
# Open Vivado GUI Script
# Usage: ./open.sh

# Navigate to project root
cd "$(dirname "$0")"

# Source Vivado environment
source scripts/vivado_env.sh

echo "========================================"
echo "Opening Vivado GUI"
echo "========================================"

# Ensure project exists
ensure_project

# Open GUI
echo "Launching Vivado GUI with project: posit_research"
run_vivado_gui

echo "Vivado GUI launched in background."
echo "Close the GUI window when finished."
