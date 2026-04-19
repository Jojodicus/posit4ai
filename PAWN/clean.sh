#!/bin/bash

cd "$(dirname "$0")"

echo "Cleaning Vivado project artifacts..."

rm -rf vivado_proj/
rm -f *.log *.jou *.pb *.str
rm -rf .Xil/
rm -rf scripts/.Xil/
rm -rf harness/.Xil/
rm -f results.csv
rm -rf reports/

echo "Clean complete."
