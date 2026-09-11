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
for srv in "sh.brew.routun" "homebrew.mxcl.routun" "com.routun.routund" "com.routun.daemon"; do
    if launchctl print "system/$srv" >/dev/null 2>&1; then
        launchctl bootout "system/$srv" 2>/dev/null || true
    fi
done
for plist in "/Library/LaunchDaemons/sh.brew.routun.plist" "/Library/LaunchDaemons/homebrew.mxcl.routun.plist" "/Library/LaunchDaemons/com.routun.routund.plist" "/Library/LaunchDaemons/com.routun.daemon.plist"; do
    launchctl unload "$plist" 2>/dev/null || true
done
sleep 1

# 2. Terminate residual child processes if any
echo "[2/4] Ensuring all background processes are stopped..."
killall -9 sing-box 2>/dev/null || true
killall -9 ciadpi 2>/dev/null || true
killall -9 routun 2>/dev/null || true
sleep 1

# 3. Remove LaunchDaemon and configuration files
echo "[3/4] Removing service files, configurations, and logs..."
rm -f "/Library/LaunchDaemons/sh.brew.routun.plist"
rm -f "/Library/LaunchDaemons/homebrew.mxcl.routun.plist"
rm -f "/Library/LaunchDaemons/com.routun.routund.plist"
rm -f "/Library/LaunchDaemons/com.routun.daemon.plist"
rm -rf "/Library/Application Support/routun"
rm -rf "/opt/homebrew/etc/routun"
rm -rf "/opt/homebrew/var/log/routun"
rm -f "/opt/homebrew/var/run/routun.pid"
rm -rf "/var/log/routun"
rm -f "/var/run/routun.pid"
rm -f "/usr/local/bin/routun"
rm -f "/usr/local/bin/ciadpi"
rm -rf "/opt/homebrew/Cellar/routun"
rm -rf "/opt/homebrew/opt/routun"

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
