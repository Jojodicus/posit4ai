#!/usr/bin/env bash
# board_run.sh -- ssh helper: program bitstream and run a command on the board.
#
# Usage:
#   ./scripts/board_run.sh [BOARD_IP] [BOARD_USER] [CMD...]
#
# With no CMD, opens an interactive shell.
#
# Bitstream programming uses the Zynq xdevcfg interface:
#   dd if=<bit> of=/dev/xdevcfg
# Available on stock PetaLinux without extra drivers.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOARD_IP="${1:-192.168.1.100}"
BOARD_USER="${2:-root}"
shift 2 2>/dev/null || true

REMOTE="${BOARD_USER}@${BOARD_IP}"
DEST="/home/${BOARD_USER}/pawn"
BIT_REMOTE="${DEST}/zynq_accel_top.bit"

if [ $# -eq 0 ]; then
    ssh "${REMOTE}"
else
    ssh "${REMOTE}" "$@"
fi
