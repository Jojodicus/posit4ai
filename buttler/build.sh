#!/bin/bash
set -e

# Build server (cross-compile for Zedboard ARMv7)
echo "==> Building server..."
make -C server
echo "    server/server ready."

# Set up client venv
echo "==> Setting up client venv..."
cd client && uv sync
echo "    client/.venv ready."

echo ""
echo "Done. See README.md for usage."
