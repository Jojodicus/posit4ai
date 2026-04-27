#!/bin/bash
# Fmax Search
# Binary-searches the maximum implementation frequency using full P&R runs.
# Starts at 100 MHz and uses the WNS-based interpolation formula to pick
# each candidate.  Results are written to reports/fmax_search.log.

set -e
cd "$(dirname "$0")"
source scripts/vivado_env.sh

echo "========================================"
echo "Fmax Search (impl-based binary search)"
echo "Starting at 100 MHz"
echo "========================================"
echo ""
echo "Each iteration runs full synthesis + P&R."
echo "This may take a long time."
echo ""

mkdir -p reports
run_vivado_batch scripts/find_fmax.tcl

echo ""
echo "Detailed log: reports/fmax_search.log"
echo "========================================"
