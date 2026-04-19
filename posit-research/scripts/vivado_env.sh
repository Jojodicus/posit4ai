#!/bin/bash
# Vivado Environment Setup Helper
# Sources Vivado settings and provides helper functions for batch/GUI invocation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIVADO_SYMLINK="$PROJECT_ROOT/vivado"

prompt_yes_no() {
    local prompt="$1"
    local response
    while true; do
        read -p "$prompt [y/n]: " response
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer y or n" ;;
        esac
    done
}

resolve_vivado_path() {
    if [ -L "$VIVADO_SYMLINK" ]; then
        echo "$(readlink -f "$VIVADO_SYMLINK")"
    else
        echo ""
    fi
}

vivado_install_dir() {
    local vdir
    vdir=$(resolve_vivado_path)
    if [ -n "$vdir" ] && [ -d "$vdir" ]; then
        echo "$vdir"
        return 0
    fi
    return 1
}

if ! vivado_install_dir &>/dev/null; then
    echo "No Vivado installation found."
    echo "Would you like to search for Vivado now? (Recommended)"
    if prompt_yes_no "Search for Vivado?"; then
        "$SCRIPT_DIR/find_vivado.sh"
    else
        echo "ERROR: Cannot proceed without Vivado installation"
        exit 1
    fi
fi

VIVADO_DIR=$(vivado_install_dir)
VIVADO_SETTINGS="$VIVADO_DIR/.settings64-Vivado.sh"

if [ ! -f "$VIVADO_SETTINGS" ]; then
    echo "ERROR: Vivado settings file not found at: $VIVADO_SETTINGS"
    echo "Please check your Vivado installation or re-run the finder:"
    echo "  ./scripts/find_vivado.sh"
    exit 1
fi

source "$VIVADO_SETTINGS"

export VIVADO_BIN="$VIVADO_DIR/bin/vivado"
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_FILE="$PROJECT_ROOT/vivado_proj/posit_research.xpr"

# Helper function: Run Vivado in batch mode with a TCL script
# Usage: run_vivado_batch <tcl_script> [extra_args]
run_vivado_batch() {
    local tcl_script="$1"
    shift
    "$VIVADO_BIN" -mode batch -notrace -source "$tcl_script" "$@"
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
