#!/usr/bin/env bash
# board_push.sh -- copy bitstream, binaries, and scripts to the Zedboard.
#
# Usage:  ./scripts/board_push.sh [BOARD_IP] [BOARD_USER]
#         Defaults: 192.168.1.100  root
#
# Assumptions:
#   - PetaLinux is booted on the board (ssh + scp reachable).
#   - Bitstream is already generated (./impl.sh).
#   - Binaries are already compiled (cd sw && make CROSS=arm-linux-gnueabihf-).

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOARD_IP="${1:-192.168.1.100}"
BOARD_USER="${2:-root}"
REMOTE="${BOARD_USER}@${BOARD_IP}"
DEST="/home/${BOARD_USER}/pawn"

BIT="${ROOT}/vivado_proj/posit_research.runs/impl_1/zynq_accel_top.bit"
BIN="${BIT}.bin"

echo "==> Pushing to ${REMOTE}:${DEST}"
ssh "${REMOTE}" "mkdir -p ${DEST}/examples"

# Bitstream: convert .bit -> .bit.bin (byte-swapped raw binary required by
# the Zynq fpga_manager sysfs interface).
if [ -f "${BIT}" ]; then
    # Source Vivado env so bootgen is on PATH
    source "${ROOT}/scripts/vivado_env.sh" >/dev/null 2>&1

    BIF="${ROOT}/vivado_proj/posit_research.runs/impl_1/convert.bif"
    echo "all: { ${BIT} }" > "${BIF}"
    bootgen -image "${BIF}" -arch zynq -process_bitstream bin -w on
    rm -f "${BIF}"

    scp "${BIN}" "${REMOTE}:${DEST}/zynq_accel_top.bin"
    echo "    bitstream (.bin): ok"
else
    echo "    WARNING: bitstream not found at ${BIT}"
    echo "             Run ./impl.sh first."
fi

# Binaries
for bin in hello_posit.elf benchmark.elf long_run_status.elf hello_posit64.elf bench_gemm.elf bench_conv.elf hello_posit2.elf; do
    src="${ROOT}/sw/examples/${bin}"
    if [ -f "${src}" ]; then
        scp "${src}" "${REMOTE}:${DEST}/examples/"
        echo "    ${bin}: ok"
    else
        echo "    WARNING: ${bin} not found -- run: cd sw && make"
    fi
done

echo ""
echo "==> On the board, program the bitstream:"
echo "      mkdir -p /lib/firmware"
echo "      echo 0 > /sys/class/fpga_manager/fpga0/flags"
echo "      cp ${DEST}/zynq_accel_top.bin /lib/firmware/"
echo "      echo zynq_accel_top.bin > /sys/class/fpga_manager/fpga0/firmware"
echo "      devmem 0xF8000008 32 0xDF0D   # SLCR unlock"
echo "      devmem 0xF8000240 32 0x0      # deassert PL resets"
echo "      devmem 0xF8000004 32 0x767B   # SLCR lock"
echo ""
echo "==> Then run:"
echo "      ${DEST}/examples/*.elf"
