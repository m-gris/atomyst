#!/bin/bash
set -euo pipefail

# Atomyst installer
# Usage: curl -fsSL https://raw.githubusercontent.com/m-gris/atomyst/main/install.sh | bash

REPO="m-gris/atomyst"
VERSION="${ATOMYST_VERSION:-latest}"
INSTALL_DIR="${ATOMYST_INSTALL_DIR:-$HOME/.local/bin}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux) echo "linux" ;;
        *) error "Unsupported operating system: $(uname -s)" ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64" ;;
        arm64|aarch64) echo "arm64" ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac
}

# Get latest version from GitHub API
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name":' \
        | sed -E 's/.*"v([^"]+)".*/\1/'
}

main() {
    local os arch binary_name download_url

    os=$(detect_os)
    arch=$(detect_arch)

    # Linux arm64 not currently supported
    if [ "$os" = "linux" ] && [ "$arch" = "arm64" ]; then
        error "Linux arm64 is not currently supported. Consider building from source."
    fi

    binary_name="atomyst-${os}-${arch}"

    info "Detecting platform: ${os}-${arch}"

    # Resolve version
    if [ "$VERSION" = "latest" ]; then
        info "Fetching latest version..."
        VERSION=$(get_latest_version)
        if [ -z "$VERSION" ]; then
            error "Could not determine latest version. Check https://github.com/${REPO}/releases"
        fi
    fi

    info "Installing atomyst v${VERSION}..."

    download_url="https://github.com/${REPO}/releases/download/v${VERSION}/${binary_name}"

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Download binary
    info "Downloading ${binary_name}..."
    if ! curl -fsSL "$download_url" -o "${INSTALL_DIR}/atomyst"; then
        error "Failed to download ${binary_name}. Check if v${VERSION} exists at https://github.com/${REPO}/releases"
    fi

    # Make executable
    chmod +x "${INSTALL_DIR}/atomyst"

    info "Installed atomyst to ${INSTALL_DIR}/atomyst"

    # Check if install dir is in PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        warn ""
        warn "Note: ${INSTALL_DIR} is not in your PATH."
        warn "Add it to your shell profile:"
        warn ""
        warn "  export PATH=\"${INSTALL_DIR}:\$PATH\""
        warn ""
    fi

    # Verify installation
    if "${INSTALL_DIR}/atomyst" --version >/dev/null 2>&1; then
        info ""
        info "Installation complete!"
        "${INSTALL_DIR}/atomyst" --version
    else
        error "Installation verification failed. The binary may not be compatible with your system."
    fi
}

main
