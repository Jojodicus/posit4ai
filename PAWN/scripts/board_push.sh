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

# Bitstream: convert .bit -> .bin (byte-swapped raw binary required by
# the Zynq fpga_manager sysfs interface).
if [ ! -f ${BIN} ]; then
    if [ -f "${BIT}" ]; then
        # Source Vivado env so bootgen is on PATH
        source "${ROOT}/scripts/vivado_env.sh" >/dev/null 2>&1

        BIF="${ROOT}/vivado_proj/posit_research.runs/impl_1/convert.bif"
        echo "all: { ${BIT} }" > "${BIF}"
        bootgen -image "${BIF}" -arch zynq -process_bitstream bin -w on
        rm -f "${BIF}"
    else
        echo "    WARNING: bitstream not found at ${BIT}"
        echo "             Run ./impl.sh first."
        exit 1
    fi
    scp "${BIN}" "${REMOTE}:${DEST}/zynq_accel_top.bin"
    echo "    bitstream (.bin): ok"
fi

# Binaries
for bin in hello_posit.elf benchmark.elf long_run_status.elf hello_posit64.elf bench_gemm.elf bench_conv.elf hello_posit2.elf \
           bench_per_op.elf bench_per_op64.elf bench_gemm64.elf bench_conv64.elf; do
    src="${ROOT}/sw/examples/${bin}"
    if [ -f "${src}" ]; then
        scp "${src}" "${REMOTE}:${DEST}/examples/"
        echo "    ${bin}: ok"
    else
        echo "    WARNING: ${bin} not found -- run: cd sw && make"
    fi
done

# Scripts
for script in load.sh bench_all.sh; do
    src="${ROOT}/sw/${script}"
    if [ -f "${src}" ]; then
        scp "${src}" "${REMOTE}:"
        ssh "${REMOTE}" "chmod +x ${script}"
        echo "    ${script}: ok"
    else
        echo "    WARNING: ${script} not found"
    fi
done

echo ""
echo "==> On the board, program and run benchmarks:"
echo "      cd ${DEST}"
echo "      ./bench_all.sh ./<bitstream>.bin quire|no-quire 32|64"
