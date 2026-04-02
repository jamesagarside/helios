#!/usr/bin/env bash
# Helios Relay installer — downloads the pre-compiled binary for your platform.
#
# Usage: curl -fsSL https://helios.argus.dev/relay/install.sh | sh
#
# Installs to ~/.local/bin/helios-relay (no admin access needed).

set -euo pipefail

REPO="jamesagarside/helios"
INSTALL_DIR="${HOME}/.local/bin"
BINARY_NAME="helios-relay"

# Detect platform
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "${OS}" in
  darwin)  PLATFORM="macos" ;;
  linux)   PLATFORM="linux" ;;
  *)       echo "Unsupported OS: ${OS}"; exit 1 ;;
esac

case "${ARCH}" in
  x86_64|amd64) ARCH="x64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *)             echo "Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

ASSET_NAME="helios-relay-${PLATFORM}-${ARCH}"

echo ""
echo "  Helios Relay Installer"
echo "  Platform: ${PLATFORM}-${ARCH}"
echo ""

# Get latest release URL
DOWNLOAD_URL=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep "browser_download_url.*${ASSET_NAME}" \
  | head -1 \
  | cut -d '"' -f 4)

if [ -z "${DOWNLOAD_URL:-}" ]; then
  echo "  No pre-built binary found for ${PLATFORM}-${ARCH}."
  echo ""
  echo "  Alternative: install from source with Dart SDK:"
  echo "    dart pub global activate helios_relay"
  echo ""
  echo "  Or compile from the repo:"
  echo "    git clone https://github.com/${REPO}.git"
  echo "    cd helios"
  echo "    dart compile exe scripts/helios_relay.dart -o helios-relay"
  echo ""
  exit 1
fi

# Download
mkdir -p "${INSTALL_DIR}"
echo "  Downloading ${ASSET_NAME}..."
curl -fsSL "${DOWNLOAD_URL}" -o "${INSTALL_DIR}/${BINARY_NAME}"
chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

echo "  Installed to ${INSTALL_DIR}/${BINARY_NAME}"
echo ""

# Check if install dir is in PATH
if ! echo "${PATH}" | tr ':' '\n' | grep -q "^${INSTALL_DIR}$"; then
  echo "  Add to your PATH:"
  echo "    export PATH=\"${INSTALL_DIR}:\${PATH}\""
  echo ""
  echo "  Or add to your shell profile (~/.zshrc or ~/.bashrc):"
  echo "    echo 'export PATH=\"${INSTALL_DIR}:\${PATH}\"' >> ~/.zshrc"
  echo ""
fi

echo "  Run with:"
echo "    helios-relay --fc-host 192.168.4.1"
echo ""
