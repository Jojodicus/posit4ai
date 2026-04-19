#!/bin/bash
# Vivado Installation Finder Script
# Searches for Vivado installation and creates a symlink for easy access

set -e

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

find_vivado_settings() {
    local search_path="$1"
    local max_depth="$2"

    timeout "$TIMEOUT_SECS" find "$search_path" -maxdepth "$max_depth" -name "settings64*.sh" -path "*/Vivado/*" 2>/dev/null | head -20
}

echo "========================================"
echo "Vivado Installation Finder"
echo "========================================"
echo ""

FOUND_VIVADO=""
TIMEOUT_SECS=60

echo "[1/6] Checking if Vivado is in PATH..."
if command -v vivado &>/dev/null; then
    VIVADO_PATH=$(command -v vivado)
    VIVADO_DIR=$(dirname "$(dirname "$VIVADO_PATH")")
    echo "Found Vivado in PATH: $VIVADO_DIR"
    if prompt_yes_no "Use this installation?"; then
        FOUND_VIVADO="$VIVADO_DIR"
    fi
fi

if [ -z "$FOUND_VIVADO" ]; then
    echo ""
    echo "[2/6] Checking for module command..."
    if command -v module &>/dev/null; then
        echo "Module command found. Testing module loads..."

        echo "  Testing 'module load vivado'..."
        if module load vivado &>/dev/null 2>&1; then
            if command -v vivado &>/dev/null; then
                VIVADO_DIR=$(dirname "$(dirname "$(command -v vivado)")")
                echo "Loaded Vivado via 'module load vivado': $VIVADO_DIR"
                if prompt_yes_no "Use this installation?"; then
                    FOUND_VIVADO="$VIVADO_DIR"
                fi
            fi
            module unload vivado &>/dev/null 2>&1 || true
        fi

        if [ -z "$FOUND_VIVADO" ]; then
            echo "  Testing 'module load Core/vivado'..."
            if module load Core/vivado &>/dev/null 2>&1; then
                if command -v vivado &>/dev/null; then
                    VIVADO_DIR=$(dirname "$(dirname "$(command -v vivado)")")
                    echo "Loaded Vivado via 'module load Core/vivado': $VIVADO_DIR"
                    if prompt_yes_no "Use this installation?"; then
                        FOUND_VIVADO="$VIVADO_DIR"
                    fi
                fi
                module unload Core/vivado &>/dev/null 2>&1 || true
            fi
        fi
    else
        echo "Module command not found. Skipping."
    fi
fi

if [ -z "$FOUND_VIVADO" ]; then
    echo ""
    echo "[3/6] Searching for Vivado installation in / (max depth 8)..."
    echo "This may take up to 1 minute..."
    SETTINGS_FILES=$(find_vivado_settings "/" 8)

    if [ -n "$SETTINGS_FILES" ]; then
        echo "Found potential installations:"
        echo "$SETTINGS_FILES" | nl -v 1
        echo ""

        if prompt_yes_no "Use one of these installations?"; then
            echo "Enter the number of your choice:"
            read -r choice
            SELECTED=$(echo "$SETTINGS_FILES" | sed -n "${choice}p")
            if [ -n "$SELECTED" ]; then
                FOUND_VIVADO=$(dirname "$SELECTED")
            fi
        fi
    else
        echo "No Vivado installations found in /"
    fi
fi

if [ -z "$FOUND_VIVADO" ]; then
    echo ""
    echo "[4/6] Searching for Vivado installation in \$HOME (max depth 8)..."
    echo "This may take up to 1 minute..."
    SETTINGS_FILES=$(find_vivado_settings "$HOME" 8)

    if [ -n "$SETTINGS_FILES" ]; then
        echo "Found potential installations:"
        echo "$SETTINGS_FILES" | nl -v 1
        echo ""

        if prompt_yes_no "Use one of these installations?"; then
            echo "Enter the number of your choice:"
            read -r choice
            SELECTED=$(echo "$SETTINGS_FILES" | sed -n "${choice}p")
            if [ -n "$SELECTED" ]; then
                FOUND_VIVADO=$(dirname "$SELECTED")
            fi
        fi
    else
        echo "No Vivado installations found in \$HOME"
    fi
fi

if [ -z "$FOUND_VIVADO" ]; then
    echo ""
    echo "========================================"
    echo "ERROR: Could not find Vivado installation"
    echo "========================================"
    echo "Please install Vivado or manually create a 'vivado' symlink"
    echo "to your Vivado installation directory."
    exit 1
fi

echo ""
echo "[5/6] Validating Vivado installation..."
if [ -f "$FOUND_VIVADO/bin/vivado" ]; then
    echo "Vivado binary found: $FOUND_VIVADO/bin/vivado"
else
    echo "ERROR: Vivado binary not found in $FOUND_VIVADO/bin/"
    exit 1
fi

if [ -f "$FOUND_VIVADO/.settings64-Vivado.sh" ]; then
    echo "Settings file found: $FOUND_VIVADO/.settings64-Vivado.sh"
else
    echo "WARNING: Settings file not found at $FOUND_VIVADO/.settings64-Vivado.sh"
fi

echo ""
echo "[6/6] Creating symlink..."
if [ -L "$VIVADO_SYMLINK" ]; then
    echo "Removing existing symlink..."
    rm "$VIVADO_SYMLINK"
fi

ln -s "$FOUND_VIVADO" "$VIVADO_SYMLINK"
echo "Created symlink: $VIVADO_SYMLINK -> $FOUND_VIVADO"

echo ""
echo "========================================"
echo "Vivado setup complete!"
echo "Symlink created at: $VIVADO_SYMLINK"
echo "========================================"
