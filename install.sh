#!/bin/bash
# Build the manual CLI, then hand all service registration to that same CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "ERROR: swiftc is required. Install Xcode Command Line Tools first."
    exit 1
fi

SINGBOX_BIN="$(command -v sing-box || true)"
if [ -z "$SINGBOX_BIN" ] || [ ! -x "$SINGBOX_BIN" ]; then
    echo "ERROR: sing-box is required. Install it first (for example: brew install sing-box)."
    exit 1
fi

CIADPI_BIN="$(command -v ciadpi || true)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/routun-install.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

if [ -z "$CIADPI_BIN" ] || [ ! -x "$CIADPI_BIN" ]; then
    echo "ciadpi not found; building ByeDPI v0.17.3 from its pinned source archive..."
    ARCHIVE="$BUILD_DIR/byedpi.tar.gz"
    EXPECTED_SHA256="0a9cb8585554c68c3e2be88c33c9bf6f99f8e8c7f54b362285adab99e262566c"
    curl --fail --location --silent --show-error \
        "https://github.com/hufrea/byedpi/archive/refs/tags/v0.17.3.tar.gz" \
        --output "$ARCHIVE"
    ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
    if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
        echo "ERROR: ByeDPI archive checksum did not match the pinned release."
        exit 1
    fi
    tar -xzf "$ARCHIVE" -C "$BUILD_DIR"
    make -C "$BUILD_DIR/byedpi-0.17.3"
    CIADPI_BIN="$BUILD_DIR/byedpi-0.17.3/ciadpi"
fi

echo "Building routun for the current Mac architecture..."
swiftc -O -target "$(uname -m)-apple-macos14.0" Sources/*.swift -o "$BUILD_DIR/routun"

echo "Installing the manual CLI to /usr/local/bin/routun..."
sudo /usr/bin/install -o root -g wheel -m 755 "$BUILD_DIR/routun" /usr/local/bin/routun

echo "Installing the protected LaunchDaemon payload..."
sudo /usr/bin/env \
    ROUTUN_CIADPI_SOURCE="$CIADPI_BIN" \
    ROUTUN_SINGBOX_SOURCE="$SINGBOX_BIN" \
    /usr/local/bin/routun install

echo "Installation complete. Use 'routun status' and 'sudo routun stop'."
