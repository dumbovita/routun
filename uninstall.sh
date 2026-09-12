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

# 1. Stop and remove launchd services across system and user domains
echo "[1/3] Stopping and unregistering all launchd services..."
ALL_SERVICES=("com.routun.routund" "com.routun.daemon" "sh.brew.routun" "homebrew.mxcl.routun")

for srv in "${ALL_SERVICES[@]}"; do
    launchctl bootout "system/$srv" 2>/dev/null || true
    for uid in $(dscl . -list /Users UniqueID 2>/dev/null | awk '$2 >= 500 {print $2}'); do
        launchctl bootout "gui/$uid/$srv" 2>/dev/null || true
    done
done

ALL_PLISTS=(
    "/Library/LaunchDaemons/com.routun.routund.plist"
    "/Library/LaunchDaemons/com.routun.daemon.plist"
    "/Library/LaunchDaemons/sh.brew.routun.plist"
    "/Library/LaunchDaemons/homebrew.mxcl.routun.plist"
)

for plist in "${ALL_PLISTS[@]}"; do
    launchctl unload "$plist" 2>/dev/null || true
    rm -f "$plist"
done

# Remove any user-level LaunchAgents
for user_dir in /Users/*; do
    if [ -d "$user_dir/Library/LaunchAgents" ]; then
        rm -f "$user_dir/Library/LaunchAgents/sh.brew.routun.plist"
        rm -f "$user_dir/Library/LaunchAgents/homebrew.mxcl.routun.plist"
        rm -f "$user_dir/Library/LaunchAgents/com.routun."*
    fi
done
sleep 1

# 2. Terminate residual child processes if any
killall -TERM sing-box 2>/dev/null || true
killall -TERM ciadpi 2>/dev/null || true

# 3. Remove service files, configurations, and logs
echo "[2/2] Removing service files, configurations, and logs..."
rm -rf "/Library/Application Support/routun"
rm -rf "/var/log/routun"
rm -f "/var/run/routun.pid"
rm -f "/usr/local/bin/routun"

echo "============================================================"
echo " routun service and files have been removed."
echo " Network routing is in its native macOS state."
echo "============================================================"
