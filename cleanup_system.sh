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

format_kb() {
    local kb="$1"
    if [ "$kb" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.2f GB\", $kb/1048576}"
    elif [ "$kb" -ge 1024 ]; then
        awk "BEGIN {printf \"%.2f MB\", $kb/1024}"
    else
        echo "${kb} KB"
    fi
}

START_USED_KB=$(df -kP / | awk 'NR==2 {print $3}')
START_AVAIL_KB=$(df -kP / | awk 'NR==2 {print $4}')

echo "=========================================================="
echo " Starting System-Level Disk Cleanup"
echo " Initial Root Space (/):"
echo "   Used:      $(format_kb "$START_USED_KB")"
echo "   Available: $(format_kb "$START_AVAIL_KB")"
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

END_USED_KB=$(df -kP / | awk 'NR==2 {print $3}')
END_AVAIL_KB=$(df -kP / | awk 'NR==2 {print $4}')
DIFF_USED_KB=$((START_USED_KB - END_USED_KB))

echo "=========================================================="
echo " System-Level Cleanup Complete!"
echo " Disk Space Comparison (/):"
echo "   Before:    $(format_kb "$START_USED_KB") used, $(format_kb "$START_AVAIL_KB") available"
echo "   After:     $(format_kb "$END_USED_KB") used, $(format_kb "$END_AVAIL_KB") available"
if [ "$DIFF_USED_KB" -gt 0 ]; then
    echo "   Reclaimed: $(format_kb "$DIFF_USED_KB")"
else
    echo "   Reclaimed: 0 KB (no net change)"
fi
echo "=========================================================="
