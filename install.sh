#!/bin/bash
# ==============================================================================
# routun - Automated Installation & Activation Script for macOS
# ==============================================================================

set -e

# Require root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Elevating privileges to root..."
    exec sudo "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================"
echo " routun - Transparent TUN-based network routing for macOS"
echo "============================================================"

# 1. Check prerequisites
echo "[1/7] Verifying dependencies..."

CIADPI_BIN=""
for path in "/usr/local/bin/ciadpi" "/opt/homebrew/bin/ciadpi" "$(command -v ciadpi 2>/dev/null)"; do
    if [ -x "$path" ]; then
        CIADPI_BIN="$path"
        break
    fi
done

SINGBOX_BIN=""
for path in "/opt/homebrew/bin/sing-box" "/usr/local/bin/sing-box" "$(command -v sing-box 2>/dev/null)"; do
    if [ -x "$path" ]; then
        SINGBOX_BIN="$path"
        break
    fi
done

if [ -z "$CIADPI_BIN" ]; then
    echo "ERROR: 'ciadpi' (ByeDPI) executable not found."
    echo "Please place 'ciadpi' in /usr/local/bin/ciadpi and make it executable (chmod +x)."
    exit 1
fi
echo "  Found ciadpi at: $CIADPI_BIN"

if [ -z "$SINGBOX_BIN" ]; then
    echo "ERROR: 'sing-box' executable not found."
    echo "Please install it via Homebrew: brew install sing-box"
    exit 1
fi
echo "  Found sing-box at: $SINGBOX_BIN"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "ERROR: 'swiftc' compiler not found. Please install Xcode Command Line Tools: xcode-select --install"
    exit 1
fi

# 2. Build routun binary
echo "[2/7] Compiling native Swift binary (arm64/release)..."
swiftc -O Sources/*.swift -o routun
chmod 755 routun

# 3. Stop old unmanaged processes and any existing service
echo "[3/7] Stopping any existing routun or unmanaged DPI processes..."
for srv in "com.routun.routund" "com.routun.daemon"; do
    if launchctl print "system/$srv" >/dev/null 2>&1; then
        launchctl bootout "system/$srv" 2>/dev/null || true
    fi
done
rm -f "/Library/LaunchDaemons/com.routun.daemon.plist"
sleep 1

# Clean up standalone background processes gracefully
killall -TERM sing-box 2>/dev/null || true
killall -TERM ciadpi 2>/dev/null || true
sleep 1.5

# 4. Create directories with proper macOS permissions
echo "[4/7] Creating system directories..."
mkdir -p "/usr/local/bin"
mkdir -p "/Library/Application Support/routun"
mkdir -p "/var/log/routun"

chmod 755 "/Library/Application Support/routun"
chown root:wheel "/Library/Application Support/routun"

chmod 755 "/var/log/routun"
chown root:wheel "/var/log/routun"

# 5. Install binaries and configuration
echo "[5/7] Installing binaries and configuration..."
cp -f routun "/usr/local/bin/routun"
chown root:wheel "/usr/local/bin/routun"
chmod 755 "/usr/local/bin/routun"

cp -f config/singbox.json "/Library/Application Support/routun/singbox.json"
chown root:wheel "/Library/Application Support/routun/singbox.json"
chmod 644 "/Library/Application Support/routun/singbox.json"

cp -f config/routun.json "/Library/Application Support/routun/routun.json"
chown root:wheel "/Library/Application Support/routun/routun.json"
chmod 644 "/Library/Application Support/routun/routun.json"

# Validate singbox configuration
echo "  Validating sing-box configuration syntax..."
"$SINGBOX_BIN" check -c "/Library/Application Support/routun/singbox.json"

# 6. Install LaunchDaemon plist
echo "[6/7] Installing and activating LaunchDaemon..."
cp -f com.routun.routund.plist "/Library/LaunchDaemons/com.routun.routund.plist"
chown root:wheel "/Library/LaunchDaemons/com.routun.routund.plist"
chmod 644 "/Library/LaunchDaemons/com.routun.routund.plist"

# Bootstrap and kickstart the service
launchctl bootstrap system /Library/LaunchDaemons/com.routun.routund.plist 2>/dev/null || \
launchctl load -w /Library/LaunchDaemons/com.routun.routund.plist 2>/dev/null || true

launchctl kickstart -k system/com.routun.routund 2>/dev/null || true

# 7. Verification
echo "[7/7] Verifying service initialization..."
sleep 2

/usr/local/bin/routun status

# Optional automatic strategy optimization
if [ -t 0 ]; then
    echo ""
    read -r -p "Run automatic DPI strategy optimization (blockcheck) now? [y/N]: " OPT_CHOICE
    if [[ "$OPT_CHOICE" =~ ^[Yy]$ ]]; then
        /usr/local/bin/routun optimize
    fi
fi

echo ""
echo "============================================================"
echo " routun installation and activation complete!"
echo " Service is running continuously under launchd management."
echo ""
echo " Useful commands:"
echo "   routun status          - Check live service status & DPI health"
echo "   routun optimize        - Auto-detect best ByeDPI strategy profile"
echo "   routun profile list    - View and switch ByeDPI strategy profiles"
echo "   sudo routun stop       - Stop service"
echo "   sudo routun start      - Start service"
echo "   sudo routun restart    - Clean restart"
echo "   routun logs -f         - Stream live logs"
echo "   routun doctor          - Run full diagnostics"
echo "   sudo routun uninstall  - Cleanly remove service and files"
echo "============================================================"
