#!/usr/bin/env bash
# ==============================================================================
# Linux Developer Disk Cleanup - Purge All Unused Docker Resources Script
# Removes EVERYTHING in Docker not currently in active use:
#   - Stopped / exited containers
#   - Images not used by any running container (both dangling & unused tagged)
#   - Local volumes not attached to any container
#   - Unused custom networks
#   - BuildKit build cache
#
# GUARANTEE: Running containers, images in use, and attached volumes stay intact.
# Host non-Docker files are never touched.
# ==============================================================================
set -euo pipefail

DRY_RUN=false
FORCE=false

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
Usage: ./cleanup_docker_unused.sh [OPTIONS]

Remove all Docker containers, images, volumes, and build caches not currently in use.

OPTIONS:
  -n, --dry-run    Display inactive Docker items and reclaimable space without deleting.
  -f, --force, -y  Skip confirmation prompt and purge immediately.
  -h, --help       Show this help message.

WHAT GETS PURGED:
  - Stopped / created containers (not running)
  - Unused images (not referenced by running containers)
  - Unattached volumes (not mounted by any container)
  - Unused custom networks
  - Complete BuildKit builder cache

WHAT STAYS INTACT:
  - Currently running containers
  - Base and application images used by running containers
  - Volumes attached to running containers
  - Default networks (bridge, host, none)
  - All host filesystem files outside Docker
EOF
}

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force|-y|--yes)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run './cleanup_docker_unused.sh --help' for usage." >&2
            exit 1
            ;;
    esac
done

# Pre-flight Check 1: Docker CLI installed
if ! command -v docker &>/dev/null; then
    echo "Error: 'docker' CLI not found on PATH." >&2
    exit 1
fi

# Pre-flight Check 2: Docker daemon reachable
if ! docker info &>/dev/null; then
    echo "Error: Cannot connect to Docker daemon. Ensure Docker or Docker Desktop is running." >&2
    exit 1
fi

START_USED_KB=$(df -kP / | awk 'NR==2 {print $3}')
START_AVAIL_KB=$(df -kP / | awk 'NR==2 {print $4}')

echo "=========================================================="
echo " Docker Purge: All Unused Resources"
if [ "$DRY_RUN" = true ]; then
    echo " MODE: DRY RUN (inspection only, no modifications)"
else
    echo " MODE: PURGE ALL UNUSED DOCKER DATA"
fi
echo " Guaranteed: Running containers & attached volumes stay intact."
echo "=========================================================="

echo "--> Initial System Root Space (/):"
echo "   Used:      $(format_kb "$START_USED_KB")"
echo "   Available: $(format_kb "$START_AVAIL_KB")"
echo ""
echo "--> Current Docker Resource Breakdown:"
docker system df
echo "=========================================================="

# Check for stopped containers
STOPPED_CONTAINERS=$(docker ps -a --filter "status=exited" --filter "status=created" -q | wc -l)
RUNNING_CONTAINERS=$(docker ps --filter "status=running" -q | wc -l)

echo "Container Status: $RUNNING_CONTAINERS running (safe), $STOPPED_CONTAINERS stopped/dormant (to remove)."

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "[DRY-RUN] The following commands would be executed:"
    echo "  1. docker container prune -f        (Remove $STOPPED_CONTAINERS stopped containers)"
    echo "  2. docker network prune -f          (Remove unused custom networks)"
    echo "  3. docker image prune -a -f         (Remove ALL images not used by running containers)"
    echo "  4. docker volume prune -a -f        (Remove ALL volumes not attached to any container)"
    echo "  5. docker builder prune -a -f       (Remove complete BuildKit build cache)"
    echo ""
    echo "[DRY-RUN] To purge these resources, run without --dry-run."
    exit 0
fi

# Confirmation prompt unless forced
if [ "$FORCE" = false ]; then
    echo ""
    echo "WARNING: This will permanently delete:"
    echo "  - All stopped containers ($STOPPED_CONTAINERS containers)"
    echo "  - All images not currently used by running containers"
    echo "  - All volumes not currently attached to any container"
    echo "  - All BuildKit build cache"
    echo ""
    read -r -p "Are you sure you want to purge all unused Docker resources? [y/N]: " CONFIRM
    case "$CONFIRM" in
        [yY]|[yY][eE][sS])
            echo "Proceeding with Docker purge..."
            ;;
        *)
            echo "Operation cancelled by user. Nothing removed."
            exit 0
            ;;
    esac
fi

echo ""
echo "--> 1/5 Removing stopped containers..."
docker container prune -f

echo "--> 2/5 Removing unused custom networks..."
docker network prune -f

echo "--> 3/5 Removing ALL unused images..."
docker image prune -a -f

echo "--> 4/5 Removing ALL unattached volumes..."
docker volume prune -a -f 2>/dev/null || docker volume prune -f

echo "--> 5/5 Removing complete BuildKit builder cache..."
docker builder prune -a -f 2>/dev/null || docker buildx prune -a -f 2>/dev/null || true

# Sweep any remaining untagged references
docker system prune -a --volumes -f 2>/dev/null || true

END_USED_KB=$(df -kP / | awk 'NR==2 {print $3}')
END_AVAIL_KB=$(df -kP / | awk 'NR==2 {print $4}')
DIFF_USED_KB=$((START_USED_KB - END_USED_KB))

echo ""
echo "=========================================================="
echo " Docker Purge Complete!"
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
echo " Running containers, their images, and attached volumes"
echo " remain active and untouched."
echo "=========================================================="
