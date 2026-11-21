#!/usr/bin/env bash
# ==============================================================================
# Linux Developer Disk Scan & Audit (100% READ-ONLY)
# Scans filesystems, user directories, developer toolchains, container storage,
# browser caches, and system packages to find what is consuming disk space.
#
# GUARANTEE: This script is 100% strictly read-only.
# It does NOT delete, move, or modify any files or settings.
# ==============================================================================
set -uo pipefail

# ANSI color codes
if [ -t 1 ]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_DIM="\033[2m"
    C_RED="\033[31m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_BLUE="\033[34m"
    C_CYAN="\033[36m"
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
fi

THRESHOLD="100M"
RUN_DEEP=false
HOME_ONLY=false

show_help() {
    cat << EOF
Usage: ./scan_disk.sh [OPTIONS]

Scan your system to identify what is taking up disk space without modifying or deleting anything.

OPTIONS:
  -d, --deep             Perform deeper scans (e.g., node_modules across project folders).
  -t, --threshold <SIZE> Set the minimum size for the large-file scan (default: 100M).
                         Accepts standard find size suffixes: e.g., 50M, 200M, 1G.
      --home-only        Only scan the current user's home directory (\$HOME).
  -h, --help             Show this help message.

GUARANTEE:
  - 100% Read-Only: Absolutely zero files are deleted or altered.
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--deep)
            RUN_DEEP=true
            shift
            ;;
        -t|--threshold)
            THRESHOLD="$2"
            shift 2
            ;;
        --home-only)
            HOME_ONLY=true
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

header() {
    echo -e "\n${C_BOLD}${C_BLUE}==============================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}  $1${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}==============================================================================${C_RESET}"
}

subheader() {
    echo -e "\n${C_BOLD}${C_YELLOW}──▶ $1${C_RESET}"
}

get_dir_size() {
    local target="$1"
    if [ -e "$target" ]; then
        local sz
        sz=$(du -sh "$target" 2>/dev/null | awk 'NR==1 {print $1}')
        if [ -n "$sz" ]; then
            echo "$sz"
            return 0
        fi
    fi
    echo "N/A"
}

echo -e "${C_BOLD}${C_GREEN}"
cat << 'EOF'
  ___  _     _      ____                  
 / _ \(_)___| | __ / ___|  ___ __ _ _ __  
| | | | / __| |/ / \___ \ / __/ _` | '_ \ 
| |_| | \__ \   <   ___) | (_| (_| | | | |
 \___/|_|___/_|\_\ |____/ \___\__,_|_| |_|
EOF
echo -e "${C_RESET}"
echo -e "${C_DIM}Disk Usage Diagnostic & Audit Tool (Strictly Read-Only)${C_RESET}"
echo -e "${C_DIM}Timestamp: $(date)${C_RESET}\n"

# ------------------------------------------------------------------------------
# 1. Overall Filesystem Status
# ------------------------------------------------------------------------------
header "1. Filesystem Capacity & Mount Points"
df -hT -x tmpfs -x devtmpfs -x squashfs 2>/dev/null || df -h / 2>/dev/null || true

# Check inode usage
echo -e "\n${C_BOLD}Inode Usage (Filesystem Capacity):${C_RESET}"
df -i / 2>/dev/null || true

# ------------------------------------------------------------------------------
# 2. Root Filesystem (/) Top-Level Breakdown (Single Device)
# ------------------------------------------------------------------------------
if [ "$HOME_ONLY" = false ]; then
    header "2. Root Filesystem (/) Top-Level Breakdown"
    echo -e "${C_DIM}Note: Scanned with single-filesystem constraint (-x) to exclude virtual & loop mounts.${C_RESET}\n"
    { du -hx -d 1 / 2>/dev/null || true; } | sort -hr | head -n 12 | while read -r size dir; do
        [ -n "$size" ] && printf "  %-10s %s\n" "$size" "$dir"
    done
fi

# ------------------------------------------------------------------------------
# 3. User Home Directory Breakdown ($HOME)
# ------------------------------------------------------------------------------
header "3. User Home Directory ($HOME) Breakdown"
echo -e "${C_DIM}Top consumers in your home directory (including hidden configs and caches):${C_RESET}\n"
{ du -hx -d 1 "$HOME" 2>/dev/null || true; } | sort -hr | head -n 15 | while read -r size dir; do
    [ -n "$size" ] && printf "  %-10s %s\n" "$size" "$dir"
done

# ------------------------------------------------------------------------------
# 4. Detailed Component Breakdown
# ------------------------------------------------------------------------------
header "4. Detailed Component & Developer Storage Audit"

# Docker & Containers
subheader "Docker & Container Storage"
if [ -d "$HOME/.docker" ]; then
    DOCKER_HOME_SIZE=$(get_dir_size "$HOME/.docker")
    echo -e "  • Docker Desktop User Data: ${C_BOLD}${DOCKER_HOME_SIZE}${C_RESET} ($HOME/.docker)"
    if [ -f "$HOME/.docker/desktop/vms/0/data/Docker.raw" ]; then
        RAW_SIZE=$(get_dir_size "$HOME/.docker/desktop/vms/0/data/Docker.raw")
        RAW_APPARENT=$(ls -lh "$HOME/.docker/desktop/vms/0/data/Docker.raw" 2>/dev/null | awk '{print $5}' || echo "N/A")
        echo -e "    └─ VM Virtual Disk: ${C_BOLD}${RAW_SIZE}${C_RESET} on disk (max virtual capacity: ${RAW_APPARENT})"
    fi
fi
if [ -d "/var/lib/docker" ]; then
    VAR_DOCKER_SIZE=$(get_dir_size "/var/lib/docker")
    echo -e "  • System Docker Engine (/var/lib/docker): ${C_BOLD}${VAR_DOCKER_SIZE}${C_RESET}"
fi
if command -v docker >/dev/null 2>&1; then
    echo -e "\n  Docker Engine Reclaimable Assessment:"
    docker system df 2>/dev/null | sed 's/^/    /' || echo "    (Docker daemon is not running)"
fi

# Snap Packages & Runtime Environments
subheader "Snap Packages & Runtimes"
if [ -d "/var/lib/snapd" ]; then
    SNAPD_SIZE=$(get_dir_size "/var/lib/snapd")
    SNAPS_DIR_SIZE=$(get_dir_size "/var/lib/snapd/snaps")
    echo -e "  • Total snapd system storage: ${C_BOLD}${SNAPD_SIZE}${C_RESET} (/var/lib/snapd)"
    echo -e "    └─ Installed package archives: ${C_BOLD}${SNAPS_DIR_SIZE}${C_RESET} (/var/lib/snapd/snaps)"
    
    # Check for disabled snap revisions
    if command -v snap >/dev/null 2>&1; then
        DISABLED_SNAPS=$(snap list --all 2>/dev/null | grep -c "disabled" || echo "0")
        echo -e "    └─ Disabled/Old revisions retained: ${C_BOLD}${DISABLED_SNAPS}${C_RESET}"
    fi
fi
if [ -d "$HOME/snap" ]; then
    USER_SNAP_SIZE=$(get_dir_size "$HOME/snap")
    echo -e "  • User Snap Application Data: ${C_BOLD}${USER_SNAP_SIZE}${C_RESET} ($HOME/snap)"
    { du -h -d 1 "$HOME/snap" 2>/dev/null || true; } | sort -hr | head -n 4 | while read -r sz pth; do
        [ -n "$pth" ] && [ "$pth" != "$HOME/snap" ] && echo "    └─ $sz $(basename "$pth")"
    done
fi

# Web Browsers
subheader "Web Browsers (Profiles, Storage & Caches)"
check_browser() {
    local name="$1"
    local cfg="$2"
    local cch="$3"
    
    if [ -d "$cfg" ] || [ -d "$cch" ]; then
        local cfg_sz="0"
        local cch_sz="0"
        [ -d "$cfg" ] && cfg_sz=$(get_dir_size "$cfg")
        [ -d "$cch" ] && cch_sz=$(get_dir_size "$cch")
        echo -e "  • ${name}: Profile/Storage: ${C_BOLD}${cfg_sz}${C_RESET} | Cache: ${C_BOLD}${cch_sz}${C_RESET}"
        
        # Check IndexedDB / Service Workers if applicable
        if [ -d "$cfg/Default/IndexedDB" ]; then
            local idb_sz=$(get_dir_size "$cfg/Default/IndexedDB")
            echo "    └─ IndexedDB (Web App offline data): $idb_sz"
        fi
        if [ -d "$cfg/Default/Service Worker" ]; then
            local sw_sz=$(get_dir_size "$cfg/Default/Service Worker")
            echo "    └─ Service Worker Cache: $sw_sz"
        fi
    fi
}
check_browser "Brave Browser" "$HOME/.config/BraveSoftware" "$HOME/.cache/BraveSoftware"
check_browser "Google Chrome" "$HOME/.config/google-chrome" "$HOME/.cache/google-chrome"
check_browser "Chromium" "$HOME/.config/chromium" "$HOME/.cache/chromium"
if [ -d "$HOME/.mozilla" ]; then
    echo -e "  • Firefox (.mozilla): $(get_dir_size "$HOME/.mozilla")"
fi

# Developer Toolchains & Language Caches
subheader "Developer Toolchains, SDKs & Package Caches"
check_toolchain() {
    local label="$1"
    local path="$2"
    if [ -d "$path" ]; then
        local sz=$(get_dir_size "$path")
        echo -e "  • $(printf "%-30s" "$label:") ${C_BOLD}${sz}${C_RESET} ($path)"
    fi
}
check_toolchain "Go Module Cache" "$HOME/go/pkg/mod"
check_toolchain "Go Build Cache" "$HOME/.cache/go-build"
check_toolchain "Rust Toolchains (rustup)" "$HOME/.rustup"
check_toolchain "Cargo Package Cache" "$HOME/.cargo"
check_toolchain "Node Version Manager (NVM)" "$HOME/.nvm"
check_toolchain "NPM Global Cache" "$HOME/.npm"
check_toolchain "Bun Package Cache" "$HOME/.bun"
check_toolchain "OpenClaw Toolchain & Cache" "$HOME/.openclaw"
check_toolchain "Pip Download Cache" "$HOME/.cache/pip"
check_toolchain "UV Package Cache" "$HOME/.cache/uv"
check_toolchain "Playwright Browser Binaries" "$HOME/.cache/ms-playwright"
check_toolchain "Tracker3 Desktop Search Index" "$HOME/.cache/tracker3"
check_toolchain "VS Code Extensions & Cache" "$HOME/.vscode"
check_toolchain "Copilot Cache" "$HOME/.cache/copilot"

# Standalone Applications in /opt
if [ "$HOME_ONLY" = false ] && [ -d "/opt" ]; then
    subheader "Applications Installed in /opt"
    { du -h -d 1 /opt 2>/dev/null || true; } | sort -hr | while read -r sz pth; do
        if [ -n "$pth" ] && [ "$pth" != "/opt" ]; then
            echo -e "  • $(printf "%-25s" "$(basename "$pth"):") ${C_BOLD}${sz}${C_RESET}"
        fi
    done
fi

# Deep Scan: node_modules
if [ "$RUN_DEEP" = true ]; then
    subheader "Deep Scan: Largest node_modules Directories in \$HOME"
    echo -e "${C_DIM}Scanning for node_modules (pruned search)...${C_RESET}"
    { find "$HOME" -maxdepth 5 -name "node_modules" -type d -prune -exec du -sh {} + 2>/dev/null || true; } | sort -hr | head -n 10 | while read -r sz pth; do
        [ -n "$sz" ] && printf "  • %-10s %s\n" "$sz" "$pth"
    done
fi

# ------------------------------------------------------------------------------
# 5. Largest Single Files
# ------------------------------------------------------------------------------
header "5. Largest Individual Files in \$HOME (Threshold: > ${THRESHOLD})"
{ find "$HOME" -xdev -type f -size "+${THRESHOLD}" -exec ls -lh {} + 2>/dev/null || true; } | awk '{print $5, $9}' | sort -hr | head -n 15 | while read -r sz pth; do
    [ -n "$sz" ] && printf "  %-10s %s\n" "$sz" "$pth"
done

# ------------------------------------------------------------------------------
# 6. System Logs and Crash Dumps
# ------------------------------------------------------------------------------
if [ "$HOME_ONLY" = false ]; then
    header "6. System Logs, Journal & Crash Dumps"
    if command -v journalctl >/dev/null 2>&1; then
        echo -n "  • systemd-journald disk usage: "
        journalctl --disk-usage 2>/dev/null || echo "Unable to inspect"
    fi
    if [ -d "/var/cache/apt" ]; then
        APT_CACHE_SZ=$(get_dir_size "/var/cache/apt")
        echo -e "  • APT package cache (/var/cache/apt): ${C_BOLD}${APT_CACHE_SZ}${C_RESET}"
    fi
    if [ -d "/var/crash" ]; then
        CRASH_SZ=$(get_dir_size "/var/crash")
        echo -e "  • System crash reports (/var/crash): ${C_BOLD}${CRASH_SZ}${C_RESET}"
    fi
    if [ -d "/var/log" ]; then
        LOG_SZ=$(get_dir_size "/var/log")
        echo -e "  • Total /var/log: ${C_BOLD}${LOG_SZ}${C_RESET}"
    fi
fi

# ------------------------------------------------------------------------------
# 7. Summary & Recommended Action Plan
# ------------------------------------------------------------------------------
header "7. Summary & Recommended Cleanup Actions"

echo -e "To reclaim space, you can run the existing specialized cleanup scripts in this project:"
echo -e ""
echo -e "  ${C_BOLD}1. Safe Non-Docker Cleanup (User-space caches, IDEs, browsers):${C_RESET}"
echo -e "     ${C_CYAN}./cleanup_no_docker.sh -n${C_RESET}    (dry-run preview)"
echo -e "     ${C_CYAN}./cleanup_no_docker.sh${C_RESET}       (execute safe cleanup)"
echo -e ""
echo -e "  ${C_BOLD}2. Project Build Artifacts (node_modules, target/, .venv):${C_RESET}"
echo -e "     ${C_CYAN}./cleanup_artifacts.sh -n${C_RESET}    (dry-run preview)"
echo -e "     ${C_CYAN}./cleanup_artifacts.sh${C_RESET}       (execute workspace cleanup)"
echo -e ""
echo -e "  ${C_BOLD}3. Docker Cleanup (Containers, dangling images, build cache):${C_RESET}"
echo -e "     ${C_CYAN}./cleanup_docker.sh -n${C_RESET}       (dry-run preview)"
echo -e "     ${C_CYAN}./cleanup_docker.sh${C_RESET}          (safe prune)"
echo -e "     ${C_CYAN}./cleanup_docker_unused.sh${C_RESET}   (full purge of unused images/volumes)"
echo -e ""
if [ "$HOME_ONLY" = false ]; then
    echo -e "  ${C_BOLD}4. System Cleanup (Requires sudo - journals, apt, disabled snaps):${C_RESET}"
    echo -e "     ${C_CYAN}sudo ./cleanup_system.sh${C_RESET}"
    echo -e ""
fi
echo -e "${C_GREEN}Scan complete. No files were deleted or modified.${C_RESET}\n"
