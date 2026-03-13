#!/bin/bash
# Vivado Environment Setup Helper
# Sources Vivado settings and provides helper functions for batch/GUI invocation

# Vivado installation path
VIVADO_SETTINGS="/tools/Xilinx/2025.2/Vivado/.settings64-Vivado.sh"

# Check if Vivado settings file exists
if [ ! -f "$VIVADO_SETTINGS" ]; then
    echo "ERROR: Vivado settings file not found at: $VIVADO_SETTINGS"
    echo "Please update VIVADO_SETTINGS path in scripts/vivado_env.sh"
    exit 1
fi

# Source Vivado environment
source "$VIVADO_SETTINGS"

# Export convenience variables
export VIVADO_BIN="/tools/Xilinx/2025.2/Vivado/bin/vivado"
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_FILE="$PROJECT_ROOT/vivado_proj/posit_research.xpr"

# Helper function: Run Vivado in batch mode with a TCL script
# Usage: run_vivado_batch <tcl_script> [extra_args]
run_vivado_batch() {
    local tcl_script="$1"
    shift
    "$VIVADO_BIN" -mode batch -source "$tcl_script" "$@"
}

# Helper function: Run Vivado in GUI mode
# Usage: run_vivado_gui [project_file]
run_vivado_gui() {
    local project="${1:-$PROJECT_FILE}"
    if [ -f "$project" ]; then
        "$VIVADO_BIN" "$project" &
    else
        echo "ERROR: Project file not found: $project"
        echo "Run ./build.sh or ./open.sh to create the project first"
        exit 1
    fi
}

# Helper function: Check if project exists
project_exists() {
    [ -f "$PROJECT_FILE" ]
}

# Helper function: Create project if it doesn't exist
ensure_project() {
    if ! project_exists; then
        echo "Project not found. Creating new project..."
        run_vivado_batch "$PROJECT_ROOT/scripts/project_setup.tcl"
    fi
}
