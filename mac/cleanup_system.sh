#!/usr/bin/env bash
# ==============================================================================
# macOS Developer Disk Cleanup - System Space Script (Requires sudo)
# Safely reclaims macOS system-level caches, Homebrew cache, system diagnostic
# reports, and stale system temporary files.
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
echo " Starting macOS System-Level Disk Cleanup"
echo " Initial Root Space (/):"
echo "   Used:      $(format_kb "$START_USED_KB")"
echo "   Available: $(format_kb "$START_AVAIL_KB")"
echo "=========================================================="

# 1. Homebrew Cache & Autoremove (Run as the invoking non-root user)
TARGET_USER="${SUDO_USER:-$USER}"
if [ -n "${SUDO_USER:-}" ] && command -v brew &>/dev/null; then
    echo "--> Running Homebrew cleanup as user $TARGET_USER..."
    sudo -u "$TARGET_USER" brew cleanup -s 2>/dev/null || true
    sudo -u "$TARGET_USER" brew autoremove 2>/dev/null || true
elif command -v brew &>/dev/null; then
    echo "--> Running Homebrew cleanup..."
    brew cleanup -s 2>/dev/null || true
    brew autoremove 2>/dev/null || true
fi

# 2. System Diagnostic Reports & Crash Dumps
if [ -d "/Library/Logs/DiagnosticReports" ]; then
    echo "--> Cleaning system crash and diagnostic reports in /Library/Logs/DiagnosticReports..."
    find /Library/Logs/DiagnosticReports -type f \( -name "*.crash" -o -name "*.ips" -o -name "*.diag" \) -delete 2>/dev/null || true
fi

# 3. System-wide Caches in /Library/Caches
if [ -d "/Library/Caches" ]; then
    echo "--> Vacuuming stale items in /Library/Caches..."
    find /Library/Caches -mindepth 1 -maxdepth 2 -type f -atime +14 -delete 2>/dev/null || true
fi

# 4. Stale System Temporary Files in /private/var/tmp
if [ -d "/private/var/tmp" ]; then
    echo "--> Removing stale temporary files older than 7 days in /private/var/tmp..."
    find /private/var/tmp -mindepth 1 -mtime +7 -delete 2>/dev/null || true
fi

# 5. Flush Directory Service & DNS Cache
echo "--> Flushing DNS and directory service caches..."
dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

# 6. Check Time Machine local snapshots (information only)
if command -v tmutil &>/dev/null; then
    echo "--> Checking Time Machine local snapshots..."
    tmutil listlocalsnapshots / 2>/dev/null || true
fi

END_USED_KB=$(df -kP / | awk 'NR==2 {print $3}')
END_AVAIL_KB=$(df -kP / | awk 'NR==2 {print $4}')
DIFF_USED_KB=$((START_USED_KB - END_USED_KB))

echo "=========================================================="
echo " macOS System-Level Cleanup Complete!"
echo " Disk Space Comparison (/):"
echo "   Before:    $(format_kb "$START_USED_KB") used, $(format_kb "$START_AVAIL_KB") available"
echo "   After:     $(format_kb "$END_USED_KB") used, $(format_kb "$END_AVAIL_KB") available"
if [ "$DIFF_USED_KB" -gt 0 ]; then
    echo "   Reclaimed: $(format_kb "$DIFF_USED_KB")"
else
    echo "   Reclaimed: 0 KB (no net change)"
fi
echo "=========================================================="
