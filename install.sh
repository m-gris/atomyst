#!/bin/bash
set -euo pipefail

# Atomyst installer
# Usage: curl -fsSL https://raw.githubusercontent.com/m-gris/atomyst/main/install.sh | bash

REPO="m-gris/atomyst"
VERSION="${ATOMYST_VERSION:-latest}"
INSTALL_DIR="${ATOMYST_INSTALL_DIR:-$HOME/.local/share/atomyst}"
BIN_DIR="${ATOMYST_BIN_DIR:-$HOME/.local/bin}"

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
    local os arch tarball_name download_url tmp_dir

    os=$(detect_os)
    arch=$(detect_arch)

    # Check for unsupported platforms
    if [ "$os" = "linux" ] && [ "$arch" = "arm64" ]; then
        error "Linux arm64 is not currently supported. Consider building from source."
    fi
    if [ "$os" = "darwin" ] && [ "$arch" = "x86_64" ]; then
        error "macOS x86_64 (Intel) is not currently supported. Consider building from source or using Rosetta."
    fi

    tarball_name="atomyst-${os}-${arch}.tar.gz"

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

    download_url="https://github.com/${REPO}/releases/download/v${VERSION}/${tarball_name}"

    # Create temp directory
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT

    # Download tarball
    info "Downloading ${tarball_name}..."
    if ! curl -fsSL "$download_url" -o "${tmp_dir}/${tarball_name}"; then
        error "Failed to download ${tarball_name}. Check if v${VERSION} exists at https://github.com/${REPO}/releases"
    fi

    # Extract and install
    info "Extracting..."
    tar -xzf "${tmp_dir}/${tarball_name}" -C "$tmp_dir"

    # Remove old installation if exists
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"

    # Move files to install directory
    mv "${tmp_dir}/atomyst/"* "$INSTALL_DIR/"
    chmod +x "${INSTALL_DIR}/atomyst"

    # Create symlink in bin directory
    ln -sf "${INSTALL_DIR}/atomyst" "${BIN_DIR}/atomyst"

    info "Installed atomyst to ${INSTALL_DIR}/"
    info "Symlinked to ${BIN_DIR}/atomyst"

    # Check if bin dir is in PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
        warn ""
        warn "Note: ${BIN_DIR} is not in your PATH."
        warn "Add it to your shell profile:"
        warn ""
        warn "  export PATH=\"${BIN_DIR}:\$PATH\""
        warn ""
    fi

    # Verify installation
    if "${BIN_DIR}/atomyst" --version >/dev/null 2>&1; then
        info ""
        info "Installation complete!"
        "${BIN_DIR}/atomyst" --version
    else
        error "Installation verification failed. The binary may not be compatible with your system."
    fi
}

main
