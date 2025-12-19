#!/bin/bash
# Keyva CLI Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/seracreativo/keyva-cli/main/install.sh | bash

set -e

REPO="seracreativo/keyva-cli"
INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="keyva"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}$1${NC}"; }
success() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
error() { echo -e "${RED}$1${NC}"; exit 1; }

# Detect OS and architecture
detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$OS" in
        darwin) OS="darwin" ;;
        linux) OS="linux" ;;
        *) error "Unsupported OS: $OS" ;;
    esac

    case "$ARCH" in
        arm64|aarch64) ARCH="arm64" ;;
        x86_64) ARCH="x86_64" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac
}

# Get latest version from GitHub
get_latest_version() {
    info "Checking latest version..."
    LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [ -z "$LATEST" ]; then
        error "Failed to fetch latest version from GitHub"
    fi
}

# Download and install
install_binary() {
    local url="https://github.com/$REPO/releases/download/v$LATEST/keyva-$LATEST-$ARCH.tar.gz"
    local tmp_dir=$(mktemp -d)

    info "Downloading keyva v$LATEST..."

    if ! curl -fsSL "$url" -o "$tmp_dir/keyva.tar.gz"; then
        rm -rf "$tmp_dir"
        error "Download failed. Check if release exists for your architecture ($ARCH)"
    fi

    # Extract
    tar -xzf "$tmp_dir/keyva.tar.gz" -C "$tmp_dir"

    if [ ! -f "$tmp_dir/keyva" ]; then
        rm -rf "$tmp_dir"
        error "Extraction failed - binary not found in archive"
    fi

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Install
    mv "$tmp_dir/keyva" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"

    # Cleanup
    rm -rf "$tmp_dir"
}

# Setup PATH in shell config
setup_path() {
    # Check if already in PATH
    if echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        return 0
    fi

    local shell_config=""
    local shell_name=$(basename "$SHELL")

    case "$shell_name" in
        zsh)  shell_config="$HOME/.zshrc" ;;
        bash)
            if [ -f "$HOME/.bash_profile" ]; then
                shell_config="$HOME/.bash_profile"
            else
                shell_config="$HOME/.bashrc"
            fi
            ;;
        fish) shell_config="$HOME/.config/fish/config.fish" ;;
    esac

    if [ -n "$shell_config" ]; then
        local export_line='export PATH="$HOME/.local/bin:$PATH"'

        # Check if already added
        if [ -f "$shell_config" ] && grep -q '.local/bin' "$shell_config" 2>/dev/null; then
            return 0
        fi

        echo "" >> "$shell_config"
        echo "# Keyva CLI" >> "$shell_config"
        echo "$export_line" >> "$shell_config"

        warn "Added $INSTALL_DIR to PATH in $shell_config"
        warn "Run: source $shell_config (or restart terminal)"
    fi
}

# Main
main() {
    echo ""
    success "Keyva CLI Installer"
    echo ""

    detect_platform
    get_latest_version

    # Check current version
    if command -v keyva &>/dev/null; then
        CURRENT=$(keyva --version 2>/dev/null || echo "0.0.0")
        if [ "$CURRENT" = "$LATEST" ]; then
            success "Already up to date (v$LATEST)"
            exit 0
        fi
        info "Updating v$CURRENT → v$LATEST"
    else
        info "Installing v$LATEST"
    fi

    install_binary
    setup_path

    echo ""
    success "✓ Keyva CLI v$LATEST installed to $INSTALL_DIR/keyva"
    echo ""
    echo "Run 'keyva' to start"
    echo ""
}

main
