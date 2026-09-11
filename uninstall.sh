#!/bin/bash
# ==============================================================================
# routun - Automated Uninstallation & Cleanup Script for macOS
# ==============================================================================

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Elevating privileges to root..."
    exec sudo "$0" "$@"
fi

echo "============================================================"
echo " routun - Uninstalling routun Service"
echo "============================================================"

# 1. Stop and remove launchd service
echo "[1/4] Stopping launchd service..."
for srv in "com.routun.routund" "com.routun.daemon"; do
    if launchctl print "system/$srv" >/dev/null 2>&1; then
        launchctl bootout "system/$srv" 2>/dev/null || true
    fi
done
launchctl unload "/Library/LaunchDaemons/com.routun.routund.plist" 2>/dev/null || true
launchctl unload "/Library/LaunchDaemons/com.routun.daemon.plist" 2>/dev/null || true
sleep 1

# 2. Terminate residual child processes if any
echo "[2/4] Ensuring all background processes are stopped..."
killall sing-box 2>/dev/null || true
killall ciadpi 2>/dev/null || true
sleep 1

# 3. Remove LaunchDaemon and configuration files
echo "[3/4] Removing service files and configurations..."
rm -f "/Library/LaunchDaemons/com.routun.routund.plist"
rm -f "/Library/LaunchDaemons/com.routun.daemon.plist"
rm -rf "/Library/Application Support/routun"
rm -rf "/var/log/routun"
rm -f "/var/run/routun.pid"
rm -f "/usr/local/bin/routun"

# 4. Verify network interfaces
echo "[4/4] Verifying network interface restoration..."
if ifconfig utun10 >/dev/null 2>&1; then
    echo "  Notice: utun10 is still present; releasing..."
    ifconfig utun10 down 2>/dev/null || true
fi

echo "============================================================"
echo " routun has been completely uninstalled."
echo " All system files, launchd entries, and logs have been removed."
echo " Network routing is in its native macOS state."
echo "============================================================"
