#!/usr/bin/env bash
# ==============================================================================
# macOS Developer Disk Cleanup - Dedicated Docker Cleanup Script
# ONLY touches Docker resources (containers, images, build cache, networks, volumes).
# Host programmer files, macOS caches, and non-Docker data are NOT touched.
# ==============================================================================
set -euo pipefail

CLEAN_ALL_IMAGES=false
CLEAN_VOLUMES=false
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
Usage: ./mac/cleanup_docker.sh [OPTIONS]

Reclaim disk space occupied exclusively by Docker on macOS.

OPTIONS:
  -a, --all        Prune ALL unused images (not just dangling ones)
                   and all builder cache.
  -v, --volumes    Prune unused Docker volumes (WARNING: removes unmounted
                   data volumes; use only if you don't need orphan volume data).
  -n, --dry-run    Display current Docker disk breakdown without deleting anything.
  -h, --help       Show this help message.

DEFAULT BEHAVIOR (Safe Prune):
  - Prunes stopped containers
  - Prunes dangling images (<none>:<none>)
  - Prunes dangling / untagged build cache
  - Prunes unused Docker networks
  - Leaves running containers, tagged images, and volumes intact.
  - ZERO changes to any files outside Docker.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--all)
            CLEAN_ALL_IMAGES=true
            shift
            ;;
        -v|--volumes)
            CLEAN_VOLUMES=true
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
            echo "Run './mac/cleanup_docker.sh --help' for usage." >&2
            exit 1
            ;;
    esac
done

if ! command -v docker &>/dev/null; then
    echo "Error: 'docker' CLI is not installed or not in PATH." >&2
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "Error: Cannot connect to the Docker daemon." >&2
    echo "Ensure Docker Desktop for Mac is running." >&2
    exit 1
fi

START_USED_KB=$(df -kP / | awk 'NR==2 {print $3}')
START_AVAIL_KB=$(df -kP / | awk 'NR==2 {print $4}')

echo "=========================================================="
echo " macOS Docker-Only Disk Cleanup (DOCKER ONLY)"
echo " Guaranteed: Non-Docker files and macOS caches are untouched."
if [ "$DRY_RUN" = true ]; then
    echo " MODE: DRY RUN (no modifications will be made)"
elif [ "$CLEAN_ALL_IMAGES" = true ]; then
    echo " MODE: DEEP PRUNE (pruning all unused images & all build cache)"
else
    echo " MODE: SAFE PRUNE (dangling images & build cache only)"
fi
if [ "$CLEAN_VOLUMES" = true ]; then
    echo " VOLUMES: Unused volumes WILL be pruned"
fi
echo "=========================================================="

echo "--> Initial System Root Space (/):"
echo "   Used:      $(format_kb "$START_USED_KB")"
echo "   Available: $(format_kb "$START_AVAIL_KB")"
echo ""
echo "--> Initial Docker Disk Breakdown:"
docker system df
echo "=========================================================="

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "[DRY-RUN] The following actions would be performed:"
    echo "  1. docker container prune -f (Remove stopped containers)"
    echo "  2. docker network prune -f (Remove unused custom networks)"
    if [ "$CLEAN_ALL_IMAGES" = true ]; then
        echo "  3. docker image prune -a -f (Remove ALL unused images)"
        echo "  4. docker builder prune -a -f (Remove ALL build cache)"
    else
        echo "  3. docker image prune -f (Remove dangling images only)"
        echo "  4. docker builder prune -f (Remove dangling build cache only)"
    fi
    if [ "$CLEAN_VOLUMES" = true ]; then
        echo "  5. docker volume prune -f (Remove unused local volumes)"
    fi
    echo ""
    echo "[DRY-RUN] To execute, run without --dry-run."
    exit 0
fi

# 1. Stopped Containers
echo "--> 1/5 Pruning stopped containers..."
docker container prune -f

# 2. Unused Networks
echo "--> 2/5 Pruning unused networks..."
docker network prune -f

# 3. Images (Dangling or All Unused)
if [ "$CLEAN_ALL_IMAGES" = true ]; then
    echo "--> 3/5 Pruning ALL unused Docker images..."
    docker image prune -a -f
else
    echo "--> 3/5 Pruning dangling Docker images (<none>:<none>)..."
    docker image prune -f
fi

# 4. Build Cache
if [ "$CLEAN_ALL_IMAGES" = true ]; then
    echo "--> 4/5 Pruning ALL build cache..."
    docker builder prune -a -f 2>/dev/null || docker buildx prune -a -f 2>/dev/null || true
else
    echo "--> 4/5 Pruning dangling/expired build cache..."
    docker builder prune -f 2>/dev/null || docker buildx prune -f 2>/dev/null || true
fi

# 5. Volumes
if [ "$CLEAN_VOLUMES" = true ]; then
    echo "--> 5/5 Pruning unused volumes..."
    docker volume prune -f
else
    echo "--> 5/5 Skipping volumes (use -v or --volumes to prune unused volumes)."
fi

# 6. Docker Desktop log rotation on macOS
for mac_log in "$HOME/Library/Containers/com.docker.docker/Data/log" "$HOME/.docker/desktop/log"; do
    if [ -d "$mac_log" ]; then
        echo "--> Cleaning rotated Docker Desktop logs in $mac_log..."
        find "$mac_log" -type f \( -name "*.log.*" -o -name "*.[0-9]" \) -delete 2>/dev/null || true
    fi
done

END_USED_KB=$(df -kP / | awk 'NR==2 {print $3}')
END_AVAIL_KB=$(df -kP / | awk 'NR==2 {print $4}')
DIFF_USED_KB=$((START_USED_KB - END_USED_KB))

echo ""
echo "=========================================================="
echo " macOS Docker Cleanup Complete!"
echo " Updated Docker Disk Breakdown:"
docker system df
echo ""
echo " Disk Space Comparison (/):"
echo "   Before:    $(format_kb "$START_USED_KB") used, $(format_kb "$START_AVAIL_KB") available"
echo "   After:     $(format_kb "$END_USED_KB") used, $(format_kb "$END_AVAIL_KB") available"
if [ "$DIFF_USED_KB" -gt 0 ]; then
    echo "   Reclaimed: $(format_kb "$DIFF_USED_KB")"
else
    echo "   Reclaimed: 0 KB (no net change)"
fi
echo "=========================================================="
echo " Guaranteed: Only Docker was cleaned. Host files, IDE caches,"
echo " and code repositories were completely untouched."
echo "=========================================================="
