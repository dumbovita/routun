#!/bin/bash
# Service removal is intentionally owned by the application, never by Homebrew.
set -euo pipefail

SERVICE_CLI="/usr/local/libexec/routun/routund"
if [ -x "$SERVICE_CLI" ]; then
    exec sudo "$SERVICE_CLI" uninstall
fi

if command -v routun >/dev/null 2>&1; then
    exec sudo "$(command -v routun)" uninstall
fi

echo "routun's protected service payload is not installed. Nothing to remove."
