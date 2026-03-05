#!/bin/bash

# Navigate to the project root (posit_research)
cd "$(dirname "$0")"

echo "Cleaning Vivado project artifacts..."

# Remove the Vivado project directory
rm -rf vivado_proj/

# Remove Vivado log and journal files
rm -f *.log *.jou *.pb *.str

# Remove IP generation artifacts
rm -rf .Xil/
rm -rf scripts/.Xil/
rm -rf harness/.Xil/

# Remove any existing CSV results
rm -f results.csv

echo "Clean complete. You can now run scripts/project_setup.tcl or scripts/find_fmax.tcl"
