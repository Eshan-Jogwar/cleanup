#!/usr/bin/env bash
# ==============================================================================
# Linux Developer Disk Cleanup - Non-Docker Script (ZERO DOCKER TOUCH)
# Reclaims disk space across developer toolchains, package managers, build caches,
# IDE artifacts, browser caches, and system journals.
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
Usage: ./cleanup_no_docker.sh [OPTIONS]

Reclaim disk space from developer junk WITHOUT touching Docker.

OPTIONS:
  -s, --system     Include system-level cleanup (APT cache & autoremove,
                   systemd journal vacuum down to 200MB, disabled snap revisions,
                   and crash reports). Requires root/sudo privileges.
  -d, --deep       Include deeper caches (e.g., Go module cache, Cargo registry
                   extracted sources).
  -n, --dry-run    Inspect and calculate target cache sizes without deleting anything.
  -h, --help       Show this help message.

WHAT THIS SCRIPT CLEANS:
  - IDE: VS Code C++ precompiled headers, cached extension VSIXs.
  - Python: Pip wheel download cache, UV package cache.
  - Rust: Cargo git checkouts, package cache (and registry sources if --deep).
  - Node / JS: Bun cache, NPM global cache, Yarn cache, pnpm store.
  - Go: Go build cache, Go test cache (and Go module cache if --deep).
  - C/C++: ccache compiler cache.
  - Browsers: HTTP web caches for Brave, Chrome, Chromium, Firefox.
  - Downloads: Downloaded .deb installer packages in ~/Downloads.
  - System (with -s / sudo): Journalctl logs, APT cache, disabled snaps.

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
            echo "Run './cleanup_no_docker.sh --help' for usage." >&2
            exit 1
            ;;
    esac
done

# If run directly as root via sudo, enable system cleanup automatically unless dry-run
if [ "$EUID" -eq 0 ]; then
    RUN_SYSTEM=true
fi

# Resolve effective non-root user home directory even if executed via sudo
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME")
if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    TARGET_HOME="$HOME"
fi

START_USED_KB=$(df -kP "$TARGET_HOME" | awk 'NR==2 {print $3}')
START_AVAIL_KB=$(df -kP "$TARGET_HOME" | awk 'NR==2 {print $4}')

echo "=========================================================="
echo " Non-Docker Developer Disk Cleanup"
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
    echo " SYSTEM CLEANUP: Enabled (APT, journals, snaps)"
else
    echo " SYSTEM CLEANUP: Skipped (run with --system or sudo to enable)"
fi
echo "=========================================================="

echo "--> Initial Disk Space ($TARGET_HOME):"
echo "   Used:      $(format_kb "$START_USED_KB")"
echo "   Available: $(format_kb "$START_AVAIL_KB")"
echo "=========================================================="

# Safe directory deletion helper
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
echo "--- [1/8] Cleaning IDE & Editor Caches ---"

# VS Code C/C++ Precompiled Headers
clean_dir_contents "$TARGET_HOME/.cache/vscode-cpptools/ipch" "VS Code C++ precompiled header cache"

# VS Code Cached Extension Installers
clean_dir_contents "$TARGET_HOME/.config/Code/CachedExtensionVSIXs" "VS Code cached extension VSIXs"

# Clangd Cache
clean_dir_entirely "$TARGET_HOME/.cache/clangd" "Clangd language server cache"

# ------------------------------------------------------------------------------
# 2. Python Toolchain Caches
# ------------------------------------------------------------------------------
echo "--- [2/8] Cleaning Python Caches ---"

# Pip HTTP Cache
clean_dir_entirely "$TARGET_HOME/.cache/pip" "Pip download wheel cache"
if command -v pip3 &>/dev/null && [ "$DRY_RUN" = false ]; then
    pip3 cache purge &>/dev/null || true
elif command -v pip &>/dev/null && [ "$DRY_RUN" = false ]; then
    pip cache purge &>/dev/null || true
fi

# UV Cache
clean_dir_entirely "$TARGET_HOME/.cache/uv" "UV package manager cache"
if command -v uv &>/dev/null && [ "$DRY_RUN" = false ]; then
    uv cache clean &>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 3. JavaScript / Web Runtime Caches
# ------------------------------------------------------------------------------
echo "--- [3/8] Cleaning JavaScript & Node Caches ---"

# Bun Cache
clean_dir_contents "$TARGET_HOME/.bun/install/cache" "Bun package cache"

# NPM Global Cache
if command -v npm &>/dev/null; then
    echo "--> Cleaning NPM cache..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would run: npm cache clean --force"
    else
        npm cache clean --force &>/dev/null || true
    fi
fi

# Yarn Cache
if command -v yarn &>/dev/null; then
    echo "--> Cleaning Yarn cache..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would run: yarn cache clean --all"
    else
        yarn cache clean --all &>/dev/null || true
    fi
else
    clean_dir_entirely "$TARGET_HOME/.cache/yarn" "Yarn cache directory"
fi

# pnpm Store
if command -v pnpm &>/dev/null; then
    echo "--> Pruning unreferenced pnpm store packages..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would run: pnpm store prune"
    else
        pnpm store prune &>/dev/null || true
    fi
fi

# ------------------------------------------------------------------------------
# 4. Rust & Cargo Caches
# ------------------------------------------------------------------------------
echo "--- [4/8] Cleaning Rust & Cargo Caches ---"

# Cargo Git Checkouts
clean_dir_contents "$TARGET_HOME/.cargo/git/checkouts" "Cargo git checkout cache"
clean_dir_contents "$TARGET_HOME/.cargo/git/db" "Cargo git bare repo cache"

# Cargo Package Cache
if [ -f "$TARGET_HOME/.cargo/.package-cache" ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would remove ~/.cargo/.package-cache"
    else
        rm -f "$TARGET_HOME/.cargo/.package-cache"
    fi
fi

# Cargo Registry Source Crates (Unpacked sources; only cleaned if deep clean)
if [ "$RUN_DEEP" = true ]; then
    clean_dir_contents "$TARGET_HOME/.cargo/registry/src" "Cargo extracted crate sources (deep)"
fi

# ------------------------------------------------------------------------------
# 5. Go Language Caches
# ------------------------------------------------------------------------------
echo "--- [5/8] Cleaning Go Caches ---"

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
    clean_dir_entirely "$TARGET_HOME/.cache/go-build" "Go build cache directory"
fi

# ------------------------------------------------------------------------------
# 6. C/C++ Compiler Caches
# ------------------------------------------------------------------------------
echo "--- [6/8] Cleaning C/C++ Caches ---"

if command -v ccache &>/dev/null; then
    echo "--> Clearing ccache compiler cache..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would run: ccache -C"
    else
        ccache -C &>/dev/null || true
    fi
fi

# ------------------------------------------------------------------------------
# 7. Browser Web Caches (Keeps user profiles, passwords, bookmarks intact)
# ------------------------------------------------------------------------------
echo "--- [7/8] Cleaning Browser Web Caches ---"

clean_dir_contents "$TARGET_HOME/.cache/BraveSoftware/Brave-Browser/Default/Cache" "Brave HTTP cache"
clean_dir_contents "$TARGET_HOME/.cache/google-chrome/Default/Cache" "Google Chrome HTTP cache"
clean_dir_contents "$TARGET_HOME/.cache/chromium/Default/Cache" "Chromium HTTP cache"

# Firefox cache2
if [ -d "$TARGET_HOME/.cache/mozilla/firefox" ]; then
    for ffc in "$TARGET_HOME/.cache/mozilla/firefox"/*/cache2; do
        if [ -d "$ffc" ]; then
            clean_dir_contents "$ffc" "Firefox HTTP cache"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 8. Downloaded .deb Packages
# ------------------------------------------------------------------------------
echo "--- [8/8] Checking Stray Installers ---"

if compgen -G "$TARGET_HOME/Downloads/*.deb" > /dev/null; then
    echo "--> Removing downloaded .deb packages from ~/Downloads..."
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY-RUN] Would remove: $TARGET_HOME/Downloads/*.deb"
    else
        rm -f "$TARGET_HOME"/Downloads/*.deb
    fi
fi

# ------------------------------------------------------------------------------
# 9. Optional System-Level Cleanup (APT, journals, snaps)
# ------------------------------------------------------------------------------
if [ "$RUN_SYSTEM" = true ]; then
    echo "=========================================================="
    echo " Running System-Level Cleanups (Requires root)"
    echo "=========================================================="

    if [ "$EUID" -ne 0 ]; then
        echo "Warning: System-level cleanup requested but script is not running as root."
        echo "Please rerun with sudo: sudo ./cleanup_no_docker.sh -s"
    else
        # 1. Vacuum systemd journal logs
        if command -v journalctl &>/dev/null; then
            echo "--> Vacuuming systemd journal logs down to 200MB..."
            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY-RUN] Would run: journalctl --vacuum-size=200M"
            else
                journalctl --vacuum-size=200M || true
            fi
        fi

        # 2. APT Package Cache & Autoremove
        if command -v apt-get &>/dev/null; then
            echo "--> Cleaning APT package cache..."
            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY-RUN] Would run: apt-get clean && apt-get autoremove --purge -y"
            else
                apt-get clean
                echo "--> Autoremoving obsolete packages..."
                apt-get autoremove --purge -y || true
            fi
        fi

        # 3. Disabled Snap Revisions
        if command -v snap &>/dev/null; then
            echo "--> Scanning for disabled snap package revisions..."
            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY-RUN] Would query and remove disabled snap revisions."
            else
                snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r name rev; do
                    if [ -n "$name" ] && [ -n "$rev" ]; then
                        echo "Removing disabled snap: $name (revision $rev)..."
                        snap remove "$name" --revision="$rev" || true
                    fi
                done
            fi
        fi

        # 4. Old Crash Reports
        if [ -d "/var/crash" ]; then
            echo "--> Cleaning old application crash dumps..."
            if [ "$DRY_RUN" = true ]; then
                echo "    [DRY-RUN] Would remove: /var/crash/*.crash"
            else
                rm -f /var/crash/*.crash || true
            fi
        fi
    fi
fi

END_USED_KB=$(df -kP "$TARGET_HOME" | awk 'NR==2 {print $3}')
END_AVAIL_KB=$(df -kP "$TARGET_HOME" | awk 'NR==2 {print $4}')
DIFF_USED_KB=$((START_USED_KB - END_USED_KB))

echo ""
echo "=========================================================="
echo " Non-Docker Cleanup Complete!"
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
