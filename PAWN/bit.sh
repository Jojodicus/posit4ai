#!/bin/bash
# Bitstream Generation

set -e
cd "$(dirname "$0")"
source scripts/vivado_env.sh

CLOCK_FREQ_MHZ="${1:-100}"

echo "========================================"
echo "Bitstream Generation"
echo "Clock Frequency: ${CLOCK_FREQ_MHZ} MHz"
echo "========================================"

export CLOCK_FREQ_MHZ
mkdir -p reports
run_vivado_batch scripts/run_bit.tcl

BIT="vivado_proj/posit_research.runs/impl_1/zynq_accel_top.bit"
BIF="vivado_proj/posit_research.runs/impl_1/convert.bif"
echo "all: { ${BIT} }" > "${BIF}"
bootgen -image "${BIF}" -arch zynq -process_bitstream bin -w on
rm -f "${BIF}"
cp ${BIT}.bin reports/zynq_accel_top.bin
