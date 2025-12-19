#!/bin/bash
# Keyva CLI Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/seracreativo/keyva-cli/main/install.sh | bash

set -e

REPO="seracreativo/keyva-cli"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="keyva"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}Installing Keyva CLI...${NC}"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    arm64|aarch64)
        ARCH_SUFFIX="arm64"
        ;;
    x86_64)
        ARCH_SUFFIX="x86_64"
        ;;
    *)
        echo -e "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
        ;;
esac

# Get latest version from GitHub
echo "Fetching latest version..."
LATEST_VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    echo -e "${RED}Failed to fetch latest version${NC}"
    exit 1
fi

echo "Latest version: v$LATEST_VERSION"

# Check if already installed and up to date
if command -v keyva &> /dev/null; then
    CURRENT_VERSION=$(keyva --version 2>/dev/null || echo "0.0.0")
    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        echo -e "${GREEN}Already up to date (v$LATEST_VERSION)${NC}"
        exit 0
    fi
    echo -e "${YELLOW}Updating from v$CURRENT_VERSION to v$LATEST_VERSION${NC}"
fi

# Download
DOWNLOAD_URL="https://github.com/$REPO/releases/download/v$LATEST_VERSION/keyva-$LATEST_VERSION-$ARCH_SUFFIX.tar.gz"
TEMP_DIR=$(mktemp -d)
TEMP_TAR="$TEMP_DIR/keyva.tar.gz"
TEMP_BIN="$TEMP_DIR/keyva"

echo "Downloading from $DOWNLOAD_URL..."
curl -fsSL "$DOWNLOAD_URL" -o "$TEMP_TAR"

# Extract to temp dir
tar -xzf "$TEMP_TAR" -C "$TEMP_DIR"

# Verify binary exists
if [ ! -f "$TEMP_BIN" ]; then
    echo -e "${RED}Error: Binary not found after extraction${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Install (may need sudo)
if [ -w "$INSTALL_DIR" ]; then
    mv "$TEMP_BIN" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
else
    echo "Installing to $INSTALL_DIR (requires sudo)..."
    sudo mv "$TEMP_BIN" "$INSTALL_DIR/$BINARY_NAME"
    sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"
fi

# Cleanup
rm -rf "$TEMP_DIR"

# Verify
if command -v keyva &> /dev/null; then
    INSTALLED_VERSION=$(keyva --version 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ Keyva CLI v$INSTALLED_VERSION installed successfully${NC}"
    echo ""
    echo "Run 'keyva' to start, or 'keyva --help' for options"
else
    echo -e "${RED}Installation failed${NC}"
    exit 1
fi
