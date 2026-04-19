#!/bin/bash
# Open Vivado GUI Script

cd "$(dirname "$0")"
source scripts/vivado_env.sh
ensure_project
run_vivado_gui
