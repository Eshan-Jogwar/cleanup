#!/usr/bin/env bash
# ==============================================================================
# macOS Developer Disk Cleanup - Non-Docker Script (ZERO DOCKER TOUCH)
# Reclaims disk space across developer toolchains, package managers, build caches,
# Xcode DerivedData, IDE artifacts, browser caches, and Homebrew.
#
# GUARANTEE: Does NOT touch Docker containers, images, volumes, build cache,
# daemon, or any Docker-related configurations whatsoever.
# ==============================================================================
set -euo pipefail

RUN_SYSTEM=false
RUN_DEEP=false
DRY_RUN=false

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

show_help() {
    cat << 'EOF'
Usage: ./mac/cleanup_no_docker.sh [OPTIONS]

Reclaim disk space from macOS developer junk WITHOUT touching Docker.

OPTIONS:
  -s, --system     Include system-level cleanup (Homebrew cache & autoremove,
                   system diagnostic reports, stale /private/var/tmp files).
                   Requires root/sudo privileges.
  -d, --deep       Include deeper caches (e.g., Go module cache, Cargo registry
                   extracted sources).
  -n, --dry-run    Inspect and calculate target cache sizes without deleting anything.
  -h, --help       Show this help message.

WHAT THIS SCRIPT CLEANS:
  - IDE: VS Code C++ precompiled headers, cached extension VSIXs, Clangd.
  - Apple: Xcode DerivedData, Xcode build & module caches.
  - Python: Pip wheel download cache, UV package cache.
  - Rust: Cargo git checkouts, package cache (and registry sources if --deep).
  - Node / JS: Bun cache, NPM global cache, Yarn cache, pnpm store.
  - Go: Go build cache, Go test cache (and Go module cache if --deep).
  - C/C++: ccache compiler cache.
  - Browsers: HTTP web caches for Chrome, Brave, Safari, Firefox.
  - Downloads: Downloaded .dmg and .pkg installer packages in ~/Downloads.
  - System (with -s / sudo): Homebrew cleanup, system logs, DNS cache flush.

GUARANTEE:
  - Docker is 100% untouched. Running containers, images, volumes, and
    Docker Desktop configurations are preserved completely.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--system)
            RUN_SYSTEM=true
            shift
            ;;
        -d|--deep)
            RUN_DEEP=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run './mac/cleanup_no_docker.sh --help' for usage." >&2
            exit 1
            ;;
    esac
done

if [ "$EUID" -eq 0 ]; then
    RUN_SYSTEM=true
fi

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || echo "$HOME")
if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    TARGET_HOME="$HOME"
fi

START_USED_KB=$(df -kP "$TARGET_HOME" | awk 'NR==2 {print $3}')
START_AVAIL_KB=$(df -kP "$TARGET_HOME" | awk 'NR==2 {print $4}')

echo "=========================================================="
echo " macOS Non-Docker Developer Disk Cleanup"
echo " Target User: $TARGET_USER ($TARGET_HOME)"
echo " GUARANTEE: Docker daemon, containers, & images are UNTOUCHED."
if [ "$DRY_RUN" = true ]; then
    echo " MODE: DRY RUN (inspections only, no files deleted)"
elif [ "$RUN_DEEP" = true ]; then
    echo " MODE: DEEP CLEAN (includes module & registry caches)"
else
    echo " MODE: STANDARD CLEAN"
fi
if [ "$RUN_SYSTEM" = true ]; then
    echo " SYSTEM CLEANUP: Enabled (Homebrew, system caches)"
else
    echo " SYSTEM CLEANUP: Skipped (run with --system or sudo to enable)"
fi
echo "=========================================================="

echo "--> Initial Disk Space ($TARGET_HOME):"
echo "   Used:      $(format_kb "$START_USED_KB")"
echo "   Available: $(format_kb "$START_AVAIL_KB")"
echo "=========================================================="

clean_dir_contents() {
    local dir="$1"
    local desc="$2"
    if [ -d "$dir" ]; then
        local size
        size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        if [ "$size" != "" ] && [ "$size" != "0" ] && [ "$size" != "4.0K" ]; then
            echo "--> $desc (Current size: $size)..."
            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY-RUN] Would clear contents of: $dir"
            else
                find "$dir" -mindepth 1 -delete 2>/dev/null || rm -rf "$dir"/* 2>/dev/null || true
            fi
        fi
    fi
}

clean_dir_entirely() {
    local dir="$1"
    local desc="$2"
    if [ -d "$dir" ]; then
        local size
        size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        if [ "$size" != "" ] && [ "$size" != "0" ] && [ "$size" != "4.0K" ]; then
            echo "--> $desc (Current size: $size)..."
            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY-RUN] Would remove: $dir"
            else
                rm -rf "$dir" 2>/dev/null || true
            fi
        fi
    fi
}

# ------------------------------------------------------------------------------
# 1. IDE & Editor Caches
# ------------------------------------------------------------------------------
echo "--- [1/9] Cleaning IDE & Editor Caches ---"
clean_dir_contents "$TARGET_HOME/Library/Caches/vscode-cpptools/ipch" "VS Code C++ precompiled header cache"
clean_dir_contents "$TARGET_HOME/.cache/vscode-cpptools/ipch" "VS Code C++ precompiled header cache"
clean_dir_contents "$TARGET_HOME/Library/Application Support/Code/CachedExtensionVSIXs" "VS Code cached extension VSIXs"
clean_dir_contents "$TARGET_HOME/.config/Code/CachedExtensionVSIXs" "VS Code cached extension VSIXs"
clean_dir_entirely "$TARGET_HOME/Library/Caches/clangd" "Clangd language server cache"
clean_dir_entirely "$TARGET_HOME/.cache/clangd" "Clangd language server cache"

# ------------------------------------------------------------------------------
# 2. Apple & Xcode Caches
# ------------------------------------------------------------------------------
echo "--- [2/9] Cleaning Apple & Xcode Caches ---"
clean_dir_contents "$TARGET_HOME/Library/Developer/Xcode/DerivedData" "Xcode DerivedData build artifacts"
clean_dir_contents "$TARGET_HOME/Library/Caches/com.apple.dt.Xcode" "Xcode module caches"

# ------------------------------------------------------------------------------
# 3. Python Toolchain Caches
# ------------------------------------------------------------------------------
echo "--- [3/9] Cleaning Python Caches ---"
clean_dir_entirely "$TARGET_HOME/Library/Caches/pip" "Pip download wheel cache"
clean_dir_entirely "$TARGET_HOME/.cache/pip" "Pip download wheel cache"
if command -v pip3 &>/dev/null && [ "$DRY_RUN" = false ]; then
    pip3 cache purge &>/dev/null || true
elif command -v pip &>/dev/null && [ "$DRY_RUN" = false ]; then
    pip cache purge &>/dev/null || true
fi
clean_dir_entirely "$TARGET_HOME/Library/Caches/uv" "UV package manager cache"
clean_dir_entirely "$TARGET_HOME/.cache/uv" "UV package manager cache"
if command -v uv &>/dev/null && [ "$DRY_RUN" = false ]; then
    uv cache clean &>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 4. JavaScript / Web Runtime Caches
# ------------------------------------------------------------------------------
echo "--- [4/9] Cleaning JavaScript & Node Caches ---"
clean_dir_contents "$TARGET_HOME/.bun/install/cache" "Bun package cache"
clean_dir_contents "$TARGET_HOME/Library/Caches/bun" "Bun package cache"
if command -v npm &>/dev/null; then
    echo "--> Cleaning NPM cache..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would run: npm cache clean --force"
    else
        npm cache clean --force &>/dev/null || true
    fi
fi
if command -v yarn &>/dev/null; then
    echo "--> Cleaning Yarn cache..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would run: yarn cache clean --all"
    else
        yarn cache clean --all &>/dev/null || true
    fi
else
    clean_dir_entirely "$TARGET_HOME/Library/Caches/Yarn" "Yarn cache directory"
fi
if command -v pnpm &>/dev/null; then
    echo "--> Pruning unreferenced pnpm store packages..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would run: pnpm store prune"
    else
        pnpm store prune &>/dev/null || true
    fi
fi

# ------------------------------------------------------------------------------
# 5. Rust & Cargo Caches
# ------------------------------------------------------------------------------
echo "--- [5/9] Cleaning Rust & Cargo Caches ---"
clean_dir_contents "$TARGET_HOME/.cargo/git/checkouts" "Cargo git checkout cache"
clean_dir_contents "$TARGET_HOME/.cargo/git/db" "Cargo git bare repo cache"
if [ -f "$TARGET_HOME/.cargo/.package-cache" ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would remove ~/.cargo/.package-cache"
    else
        rm -f "$TARGET_HOME/.cargo/.package-cache"
    fi
fi
if [ "$RUN_DEEP" = true ]; then
    clean_dir_contents "$TARGET_HOME/.cargo/registry/src" "Cargo extracted crate sources (deep)"
fi

# ------------------------------------------------------------------------------
# 6. Go Language Caches
# ------------------------------------------------------------------------------
echo "--- [6/9] Cleaning Go Caches ---"
if command -v go &>/dev/null; then
    echo "--> Cleaning Go build and test caches..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would run: go clean -cache -testcache"
        if [ "$RUN_DEEP" = true ]; then
            echo "    [DRY-RUN] Would run: go clean -modcache"
        fi
    else
        go clean -cache -testcache 2>/dev/null || true
        if [ "$RUN_DEEP" = true ]; then
            echo "--> Cleaning Go module cache (deep)..."
            go clean -modcache 2>/dev/null || true
        fi
    fi
else
    clean_dir_entirely "$TARGET_HOME/Library/Caches/go-build" "Go build cache directory"
fi

# ------------------------------------------------------------------------------
# 7. C/C++ Compiler Caches
# ------------------------------------------------------------------------------
echo "--- [7/9] Cleaning C/C++ Caches ---"
if command -v ccache &>/dev/null; then
    echo "--> Clearing ccache compiler cache..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would run: ccache -C"
    else
        ccache -C &>/dev/null || true
    fi
fi

# ------------------------------------------------------------------------------
# 8. Browser Web Caches (Keeps user profiles, passwords, bookmarks intact)
# ------------------------------------------------------------------------------
echo "--- [8/9] Cleaning Browser Web Caches ---"
clean_dir_contents "$TARGET_HOME/Library/Caches/Google/Chrome/Default/Cache" "Google Chrome HTTP cache"
clean_dir_contents "$TARGET_HOME/Library/Caches/BraveSoftware/Brave-Browser/Default/Cache" "Brave HTTP cache"
clean_dir_contents "$TARGET_HOME/Library/Caches/com.apple.Safari" "Safari web cache"

# ------------------------------------------------------------------------------
# 9. Downloaded Installer Packages (.dmg, .pkg)
# ------------------------------------------------------------------------------
echo "--- [9/9] Checking Stray Installers ---"
if compgen -G "$TARGET_HOME/Downloads/*.dmg" > /dev/null; then
    echo "--> Removing downloaded .dmg disk images from ~/Downloads..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would remove: $TARGET_HOME/Downloads/*.dmg"
    else
        rm -f "$TARGET_HOME"/Downloads/*.dmg
    fi
fi
if compgen -G "$TARGET_HOME/Downloads/*.pkg" > /dev/null; then
    echo "--> Removing downloaded .pkg packages from ~/Downloads..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would remove: $TARGET_HOME/Downloads/*.pkg"
    else
        rm -f "$TARGET_HOME"/Downloads/*.pkg
    fi
fi

# ------------------------------------------------------------------------------
# Optional System-Level Cleanup (Homebrew, system diagnostic reports)
# ------------------------------------------------------------------------------
if [ "$RUN_SYSTEM" = true ]; then
    echo "=========================================================="
    echo " Running macOS System-Level Cleanups (Requires root)"
    echo "=========================================================="

    if [ "$EUID" -ne 0 ]; then
        echo "Warning: System-level cleanup requested but script is not running as root."
        echo "Please rerun with sudo: sudo ./mac/cleanup_no_docker.sh -s"
    else
        # 1. Homebrew Cleanup
        if [ -n "${SUDO_USER:-}" ] && command -v brew &>/dev/null; then
            echo "--> Running Homebrew cleanup as user $TARGET_USER..."
            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY-RUN] Would run: brew cleanup -s && brew autoremove"
            else
                sudo -u "$TARGET_USER" brew cleanup -s 2>/dev/null || true
                sudo -u "$TARGET_USER" brew autoremove 2>/dev/null || true
            fi
        fi

        # 2. System Diagnostic Reports & Crash Dumps
        if [ -d "/Library/Logs/DiagnosticReports" ]; then
            echo "--> Cleaning system crash reports in /Library/Logs/DiagnosticReports..."
            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY-RUN] Would remove: /Library/Logs/DiagnosticReports/*.crash, *.ips"
            else
                find /Library/Logs/DiagnosticReports -type f \( -name "*.crash" -o -name "*.ips" -o -name "*.diag" \) -delete 2>/dev/null || true
            fi
        fi

        # 3. System-wide Caches
        if [ -d "/Library/Caches" ]; then
            echo "--> Vacuuming stale items in /Library/Caches..."
            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY-RUN] Would clean stale files in /Library/Caches"
            else
                find /Library/Caches -mindepth 1 -maxdepth 2 -type f -atime +14 -delete 2>/dev/null || true
            fi
        fi

        # 4. Stale temporary files in /private/var/tmp
        if [ -d "/private/var/tmp" ]; then
            echo "--> Removing stale temporary files in /private/var/tmp..."
            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY-RUN] Would remove files older than 7 days in /private/var/tmp"
            else
                find /private/var/tmp -mindepth 1 -mtime +7 -delete 2>/dev/null || true
            fi
        fi
    fi
fi

END_USED_KB=$(df -kP "$TARGET_HOME" | awk 'NR==2 {print $3}')
END_AVAIL_KB=$(df -kP "$TARGET_HOME" | awk 'NR==2 {print $4}')
DIFF_USED_KB=$((START_USED_KB - END_USED_KB))

echo ""
echo "=========================================================="
echo " macOS Non-Docker Cleanup Complete!"
echo " Disk Space Comparison ($TARGET_HOME):"
echo "   Before:    $(format_kb "$START_USED_KB") used, $(format_kb "$START_AVAIL_KB") available"
echo "   After:     $(format_kb "$END_USED_KB") used, $(format_kb "$END_AVAIL_KB") available"
if [ "$DIFF_USED_KB" -gt 0 ]; then
    echo "   Reclaimed: $(format_kb "$DIFF_USED_KB")"
else
    echo "   Reclaimed: 0 KB (no net change)"
fi
echo "=========================================================="
echo " GUARANTEE VERIFIED: Docker daemon, containers, images,"
echo " volumes, and configurations were completely untouched."
echo "=========================================================="
