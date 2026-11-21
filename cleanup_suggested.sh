#!/usr/bin/env bash
# ==============================================================================
# Targeted Developer Disk Cleanup
# Cleans the specific high-impact reclaimable items identified in scan:
# 1. Go module cache & build cache (~2.4 GB)
# 2. Playwright test browser binaries (~700 MB)
# 3. GNOME Tracker3 search index cache (~519 MB)
# 4. Brave browser HTTP cache (~828 MB)
# 5. Old/disabled Snap revisions (~200 MB, requires sudo)
# 6. Docker build cache & dangling data (~600 MB - 12 GB)
# ==============================================================================
set -euo pipefail

DRY_RUN=false
INCLUDE_SUDO=false

show_help() {
    cat << EOF
Usage: ./cleanup_suggested.sh [OPTIONS]

Reclaims high-impact disk space from developer caches and browser caches.

OPTIONS:
  -n, --dry-run    Show target sizes without deleting anything.
  -s, --system     Also remove old disabled Snap revisions (requires sudo).
  -h, --help       Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--system)
            INCLUDE_SUDO=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

echo "=========================================================="
echo " Targeted Disk Cleanup $([ "$DRY_RUN" = true ] && echo "[DRY RUN]" || echo "[LIVE]")"
echo "=========================================================="

# 1. Go Caches
if command -v go >/dev/null 2>&1; then
    echo "--> Go module cache ($HOME/go/pkg/mod) & build cache:"
    if [ "$DRY_RUN" = true ]; then
        [ -d "$HOME/go/pkg/mod" ] && du -sh "$HOME/go/pkg/mod" 2>/dev/null || true
        [ -d "$HOME/.cache/go-build" ] && du -sh "$HOME/.cache/go-build" 2>/dev/null || true
    else
        go clean -modcache 2>/dev/null || true
        go clean -cache 2>/dev/null || true
        echo "    Cleaned Go caches."
    fi
fi

# 2. Playwright browser binaries
if [ -d "$HOME/.cache/ms-playwright" ]; then
    echo "--> Playwright browser cache ($HOME/.cache/ms-playwright):"
    if [ "$DRY_RUN" = true ]; then
        du -sh "$HOME/.cache/ms-playwright" 2>/dev/null || true
    else
        rm -rf "$HOME/.cache/ms-playwright"/*
        echo "    Cleaned Playwright binaries."
    fi
fi

# 3. Tracker3 Index Cache
if [ -d "$HOME/.cache/tracker3" ]; then
    echo "--> Tracker3 search index cache ($HOME/.cache/tracker3):"
    if [ "$DRY_RUN" = true ]; then
        du -sh "$HOME/.cache/tracker3" 2>/dev/null || true
    else
        rm -rf "$HOME/.cache/tracker3"/*
        echo "    Cleaned Tracker3 cache."
    fi
fi

# 4. Brave HTTP Cache (Safe web cache, keeps cookies & logins)
if [ -d "$HOME/.cache/BraveSoftware/Brave-Browser" ]; then
    echo "--> Brave browser web cache ($HOME/.cache/BraveSoftware):"
    if [ "$DRY_RUN" = true ]; then
        du -sh "$HOME/.cache/BraveSoftware" 2>/dev/null || true
    else
        rm -rf "$HOME/.cache/BraveSoftware"/*
        echo "    Cleaned Brave HTTP cache."
    fi
fi

# 5. Docker Prune
if command -v docker >/dev/null 2>&1; then
    echo "--> Docker build cache & stopped containers:"
    if [ "$DRY_RUN" = true ]; then
        docker system df 2>/dev/null || true
    else
        docker system prune -f 2>/dev/null || true
        echo "    Pruned stopped containers & build cache."
    fi
fi

# 6. Disabled Snaps (Optional sudo)
if [ "$INCLUDE_SUDO" = true ]; then
    echo "--> Disabled snap revisions:"
    if command -v snap >/dev/null 2>&1; then
        if [ "$DRY_RUN" = true ]; then
            snap list --all | awk '/disabled/{print $1, $3}' || true
        else
            snap list --all | awk '/disabled/{print $1, $3}' |
                while read -r name rev; do
                    [ -n "$name" ] && sudo snap remove "$name" --revision="$rev" 2>/dev/null || true
                done
            echo "    Removed old snap revisions."
        fi
    fi
fi

echo "=========================================================="
echo " Done. Run ./scan_disk.sh to verify new free space."
echo "=========================================================="
