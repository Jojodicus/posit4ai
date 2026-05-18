#!/bin/bash
set -e

# Build server (cross-compile for Zedboard ARMv7)
echo "==> Building server..."
make -C server
echo "    server/server ready."

# Build posit conversion shared library
echo "==> Building client/posit_convert.so..."
make -C client
echo "    client/posit_convert.so ready."

# Set up client venv
echo "==> Setting up client venv..."
cd client && uv sync
echo "    client/.venv ready."

echo ""
echo "Done. See README.md for usage."
