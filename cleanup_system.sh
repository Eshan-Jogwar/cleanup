#!/usr/bin/env bash
# ==============================================================================
# Linux Developer Disk Cleanup - System Space Script (Requires sudo)
# Safely reclaims system journals, APT cache, disabled snaps, and crash dumps.
# ==============================================================================
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo or as root: sudo $0"
    exit 1
fi

echo "=========================================================="
echo " Starting System-Level Disk Cleanup"
echo " Initial Disk Space:"
df -h /
echo "=========================================================="

# 1. Vacuum systemd journal logs
if command -v journalctl &>/dev/null; then
    echo "--> Vacuuming systemd journal logs down to 200MB..."
    journalctl --vacuum-size=200M
fi

# 2. APT Package Cache
if command -v apt-get &>/dev/null; then
    echo "--> Cleaning APT package cache..."
    apt-get clean
    echo "--> Autoremoving obsolete packages..."
    apt-get autoremove --purge -y
fi

# 3. Disabled Snap Revisions
if command -v snap &>/dev/null; then
    echo "--> Scanning for disabled snap package revisions..."
    snap list --all | awk '/disabled/{print $1, $3}' | while read -r name rev; do
        echo "Removing disabled snap: $name (revision $rev)..."
        snap remove "$name" --revision="$rev"
    done
fi

# 4. Old Crash Reports
if [ -d "/var/crash" ]; then
    echo "--> Cleaning old application crash dumps..."
    rm -f /var/crash/*.crash
fi

echo "=========================================================="
echo " System-Level Cleanup Complete!"
echo " Updated Disk Space:"
df -h /
echo "=========================================================="
