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

echo "==> Pushing to ${REMOTE}:${DEST}"
ssh "${REMOTE}" "mkdir -p ${DEST}/examples"

# Bitstream
if [ -f "${BIT}" ]; then
    scp "${BIT}" "${REMOTE}:${DEST}/"
    echo "    bitstream: ok"
else
    echo "    WARNING: bitstream not found at ${BIT}"
    echo "             Run ./impl.sh first."
fi

# Binaries
for bin in hello_posit benchmark; do
    src="${ROOT}/sw/examples/${bin}"
    if [ -f "${src}" ]; then
        scp "${src}" "${REMOTE}:${DEST}/examples/"
        echo "    ${bin}: ok"
    else
        echo "    WARNING: ${bin} not found -- run: cd sw && make CROSS=arm-linux-gnueabihf-"
    fi
done

echo ""
echo "==> On the board, program the bitstream with:"
echo "      cat ${DEST}/zynq_accel_top.bit > /sys/class/fpga_manager/fpga0/firmware"
echo "    or use the xdevcfg interface (see board_run.sh)."
echo ""
echo "==> Then run:"
echo "      ${DEST}/examples/hello_posit"
echo "      ${DEST}/examples/benchmark 4096"
