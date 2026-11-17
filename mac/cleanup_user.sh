#!/usr/bin/env bash
# ==============================================================================
# macOS Developer Disk Cleanup - User Space Script (No sudo required)
# Safely reclaims macOS user-space package manager caches, IDE caches,
# Xcode DerivedData, and browser web caches.
# ==============================================================================
set -euo pipefail

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

START_USED_KB=$(df -kP "$HOME" | awk 'NR==2 {print $3}')
START_AVAIL_KB=$(df -kP "$HOME" | awk 'NR==2 {print $4}')

echo "=========================================================="
echo " Starting macOS User-Level Disk Cleanup"
echo " Initial Disk Space ($HOME):"
echo "   Used:      $(format_kb "$START_USED_KB")"
echo "   Available: $(format_kb "$START_AVAIL_KB")"
echo "=========================================================="

# 1. VS Code C/C++ Extension Precompiled Headers
for ipch_path in "$HOME/Library/Caches/vscode-cpptools/ipch" "$HOME/.cache/vscode-cpptools/ipch"; do
    if [ -d "$ipch_path" ]; then
        echo "--> Clearing VS Code C++ precompiled header cache ($ipch_path)..."
        find "$ipch_path" -mindepth 1 -delete 2>/dev/null || rm -rf "$ipch_path"/* 2>/dev/null || true
    fi
done

# 2. VS Code Cached Extension Installers
for vsix_path in "$HOME/Library/Application Support/Code/CachedExtensionVSIXs" "$HOME/.config/Code/CachedExtensionVSIXs"; do
    if [ -d "$vsix_path" ]; then
        echo "--> Clearing VS Code cached extension VSIXs ($vsix_path)..."
        find "$vsix_path" -mindepth 1 -delete 2>/dev/null || rm -rf "$vsix_path"/* 2>/dev/null || true
    fi
done

# 3. Pip HTTP Download Cache
for pip_path in "$HOME/Library/Caches/pip" "$HOME/.cache/pip"; do
    if [ -d "$pip_path" ]; then
        echo "--> Clearing Pip wheel download cache ($pip_path)..."
        rm -rf "$pip_path" 2>/dev/null || true
    fi
done
if command -v pip3 &>/dev/null; then
    pip3 cache purge &>/dev/null || true
elif command -v pip &>/dev/null; then
    pip cache purge &>/dev/null || true
fi

# 4. UV Cache
for uv_path in "$HOME/Library/Caches/uv" "$HOME/.cache/uv"; do
    if [ -d "$uv_path" ]; then
        echo "--> Clearing UV cache ($uv_path)..."
        rm -rf "$uv_path" 2>/dev/null || true
    fi
done
if command -v uv &>/dev/null; then
    uv cache clean &>/dev/null || true
fi

# 5. Bun Package Cache
for bun_path in "$HOME/.bun/install/cache" "$HOME/Library/Caches/bun"; do
    if [ -d "$bun_path" ]; then
        echo "--> Clearing Bun package cache ($bun_path)..."
        find "$bun_path" -mindepth 1 -delete 2>/dev/null || rm -rf "$bun_path"/* 2>/dev/null || true
    fi
done

# 6. NPM Cache
if command -v npm &>/dev/null; then
    echo "--> Cleaning NPM cache..."
    npm cache clean --force 2>/dev/null || true
fi

# 7. Go Build & Module Cache
if command -v go &>/dev/null; then
    echo "--> Cleaning Go build cache..."
    go clean -cache 2>/dev/null || true
fi

# 8. Xcode DerivedData & Developer Caches (macOS specific)
if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
    echo "--> Clearing Xcode DerivedData..."
    find "$HOME/Library/Developer/Xcode/DerivedData" -mindepth 1 -delete 2>/dev/null || true
fi
if [ -d "$HOME/Library/Caches/com.apple.dt.Xcode" ]; then
    echo "--> Clearing Xcode module & build caches..."
    find "$HOME/Library/Caches/com.apple.dt.Xcode" -mindepth 1 -delete 2>/dev/null || true
fi

# 9. Browser Web Caches (Keeps user profiles, passwords, bookmarks intact)
if [ -d "$HOME/Library/Caches/Google/Chrome/Default/Cache" ]; then
    echo "--> Clearing Google Chrome HTTP cache..."
    find "$HOME/Library/Caches/Google/Chrome/Default/Cache" -mindepth 1 -delete 2>/dev/null || true
fi
if [ -d "$HOME/Library/Caches/BraveSoftware/Brave-Browser/Default/Cache" ]; then
    echo "--> Clearing Brave HTTP cache..."
    find "$HOME/Library/Caches/BraveSoftware/Brave-Browser/Default/Cache" -mindepth 1 -delete 2>/dev/null || true
fi

# 10. Leftover Installers in ~/Downloads (.dmg, .pkg)
if compgen -G "$HOME/Downloads/*.dmg" > /dev/null; then
    echo "--> Removing downloaded .dmg disk images from Downloads..."
    rm -f "$HOME"/Downloads/*.dmg 2>/dev/null || true
fi
if compgen -G "$HOME/Downloads/*.pkg" > /dev/null; then
    echo "--> Removing downloaded .pkg installers from Downloads..."
    rm -f "$HOME"/Downloads/*.pkg 2>/dev/null || true
fi

# 11. User Diagnostic Reports (Crash logs)
if [ -d "$HOME/Library/Logs/DiagnosticReports" ]; then
    echo "--> Cleaning user crash reports in ~/Library/Logs/DiagnosticReports..."
    find "$HOME/Library/Logs/DiagnosticReports" -type f \( -name "*.crash" -o -name "*.ips" -o -name "*.diag" \) -delete 2>/dev/null || true
fi

END_USED_KB=$(df -kP "$HOME" | awk 'NR==2 {print $3}')
END_AVAIL_KB=$(df -kP "$HOME" | awk 'NR==2 {print $4}')
DIFF_USED_KB=$((START_USED_KB - END_USED_KB))

echo "=========================================================="
echo " macOS User-Level Cleanup Complete!"
echo " Disk Space Comparison ($HOME):"
echo "   Before:    $(format_kb "$START_USED_KB") used, $(format_kb "$START_AVAIL_KB") available"
echo "   After:     $(format_kb "$END_USED_KB") used, $(format_kb "$END_AVAIL_KB") available"
if [ "$DIFF_USED_KB" -gt 0 ]; then
    echo "   Reclaimed: $(format_kb "$DIFF_USED_KB")"
else
    echo "   Reclaimed: 0 KB (no net change)"
fi
echo "=========================================================="
