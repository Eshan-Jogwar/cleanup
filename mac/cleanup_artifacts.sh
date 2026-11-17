#!/usr/bin/env bash
# ==============================================================================
# macOS Developer Disk Cleanup - Project Build & Package Artifacts Script
# Discovers and removes regenerable language package directories and build caches:
#   - JavaScript / Node: node_modules, .next, .nuxt, .svelte-kit, .turbo, .parcel-cache
#   - Rust:              target/ (Cargo build artifacts)
#   - Swift / SPM:       .build (Swift Package Manager build directory)
#   - Python:            .venv, venv, .virtualenv, __pycache__, .pytest_cache, .mypy_cache, .ruff_cache
#   - Dart / Flutter:    .dart_tool
#   - iOS / CocoaPods:   Pods
#   - Java / Gradle:     .gradle
#
# GUARANTEE: Does NOT touch source code, git commits/branches, or user configs.
# All deleted items can be redownloaded/rebuilt anytime (npm install, cargo build, etc.).
# ==============================================================================
set -euo pipefail

DRY_RUN=false
FORCE=false
FILTER_TYPE="all"
SCAN_PATHS=()

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
Usage: ./mac/cleanup_artifacts.sh [OPTIONS] [DIRECTORY...]

Find and safely delete regenerable language package folders and build artifacts on macOS
(e.g., node_modules, Rust target/, Swift .build, Python .venv/venv, CocoaPods Pods, etc.).

OPTIONS:
  -n, --dry-run        Inspect and list all matching directories and total size
                       without deleting anything.
  -f, --force, -y      Skip confirmation prompt and delete immediately.
      --node           Only clean Node.js / JavaScript packages (node_modules, .next, .turbo).
      --rust           Only clean Rust / Cargo build artifacts (target/).
      --python         Only clean Python virtual environments (.venv, venv) & caches.
      --swift          Only clean Swift Package Manager build artifacts (.build).
      --type <TYPE>    Filter cleanup: all, node, rust, python, swift, flutter, gradle.
  -h, --help           Show this help message.

ARGUMENTS:
  [DIRECTORY...]       One or more directory paths to search inside (e.g. ~/Developer .).
                       If no directory is given, the script automatically scans
                       detected project folders (~/coding, ~/Developer, ~/projects, etc.) or ".".

SAFETY:
  - Excludes .git, Library, Applications, .vscode, .cache, and system paths.
  - Verifies Python venvs contain pyvenv.cfg or bin/activate before deleting.
  - Verifies Rust target folders belong to a Cargo/build project before deleting.
  - Prompts for confirmation before deleting unless -f / --force is passed.
EOF
}

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
        --node|--node-modules)
            FILTER_TYPE="node"
            shift
            ;;
        --rust|--cargo)
            FILTER_TYPE="rust"
            shift
            ;;
        --python|--venv)
            FILTER_TYPE="python"
            shift
            ;;
        --swift|--spm)
            FILTER_TYPE="swift"
            shift
            ;;
        --type)
            if [ -n "${2:-}" ]; then
                FILTER_TYPE="$2"
                shift 2
            else
                echo "Error: --type requires an argument" >&2
                exit 1
            fi
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Run './mac/cleanup_artifacts.sh --help' for usage." >&2
            exit 1
            ;;
        *)
            SCAN_PATHS+=("$1")
            shift
            ;;
    esac
done

if [ ${#SCAN_PATHS[@]} -eq 0 ]; then
    CANDIDATES=(
        "$HOME/Developer"
        "$HOME/Development"
        "$HOME/coding"
        "$HOME/projects"
        "$HOME/src"
        "$HOME/workspace"
        "$HOME/dev"
    )
    for cand in "${CANDIDATES[@]}"; do
        if [ -d "$cand" ]; then
            SCAN_PATHS+=("$cand")
        fi
    done

    if [ ${#SCAN_PATHS[@]} -eq 0 ]; then
        SCAN_PATHS=(".")
    fi
fi

RESOLVED_PATHS=()
for sp in "${SCAN_PATHS[@]}"; do
    if [ -d "$sp" ]; then
        RESOLVED_PATHS+=("$(cd "$sp" && pwd)")
    else
        echo "Warning: Directory not found, skipping: $sp" >&2
    fi
done

if [ ${#RESOLVED_PATHS[@]} -eq 0 ]; then
    echo "Error: No valid directories to scan." >&2
    exit 1
fi

PRIMARY_ROOT="${RESOLVED_PATHS[0]}"
START_USED_KB=$(df -kP "$PRIMARY_ROOT" | awk 'NR==2 {print $3}')
START_AVAIL_KB=$(df -kP "$PRIMARY_ROOT" | awk 'NR==2 {print $4}')

echo "=========================================================="
echo " macOS Project Build & Package Artifacts Cleanup"
if [ "$DRY_RUN" = true ]; then
    echo " MODE: DRY RUN (inspection only, no files deleted)"
else
    echo " MODE: ACTIVE CLEANUP"
fi
echo " Filter: $FILTER_TYPE"
echo " Initial Storage ($PRIMARY_ROOT):"
echo "   Used:      $(format_kb "$START_USED_KB")"
echo "   Available: $(format_kb "$START_AVAIL_KB")"
echo " Scanning directories:"
for rp in "${RESOLVED_PATHS[@]}"; do
    echo "   - $rp"
done
echo "=========================================================="

echo "--> Scanning for regenerable package and build directories..."

classify_and_validate() {
    local p="$1"
    local base
    base=$(basename "$p")

    # 1. Node / JavaScript
    if [[ "$base" == "node_modules" ]]; then
        if [ "$FILTER_TYPE" != "all" ] && [ "$FILTER_TYPE" != "node" ]; then return 1; fi
        echo "Node.js (node_modules)"
        return 0
    elif [[ "$base" =~ ^\.(next|nuxt|svelte-kit|turbo|parcel-cache)$ ]]; then
        if [ "$FILTER_TYPE" != "all" ] && [ "$FILTER_TYPE" != "node" ]; then return 1; fi
        echo "Frontend Cache ($base)"
        return 0
    fi

    # 2. Rust / Cargo
    if [[ "$base" == "target" ]]; then
        if [ "$FILTER_TYPE" != "all" ] && [ "$FILTER_TYPE" != "rust" ]; then return 1; fi
        local parent
        parent=$(dirname "$p")
        if [ -f "$parent/Cargo.toml" ] || [ -f "$parent/pom.xml" ] || [ -f "$p/CACHEDIR.TAG" ] || [ -d "$p/debug" ] || [ -d "$p/release" ]; then
            echo "Rust/Build (target/)"
            return 0
        fi
        return 1
    fi

    # 3. Swift Package Manager (.build)
    if [[ "$base" == ".build" ]]; then
        if [ "$FILTER_TYPE" != "all" ] && [ "$FILTER_TYPE" != "swift" ]; then return 1; fi
        local parent
        parent=$(dirname "$p")
        if [ -f "$parent/Package.swift" ]; then
            echo "Swift/SPM (.build)"
            return 0
        fi
        return 1
    fi

    # 4. Python Virtual Environments
    if [[ "$base" =~ ^(\.venv|venv|\.virtualenv|env)$ ]]; then
        if [ "$FILTER_TYPE" != "all" ] && [ "$FILTER_TYPE" != "python" ]; then return 1; fi
        if [ -f "$p/pyvenv.cfg" ] || [ -f "$p/bin/activate" ] || [ -f "$p/Scripts/activate" ]; then
            echo "Python VirtualEnv ($base)"
            return 0
        fi
        return 1
    fi

    # 5. Python Caches
    if [[ "$base" =~ ^(__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache)$ ]]; then
        if [ "$FILTER_TYPE" != "all" ] && [ "$FILTER_TYPE" != "python" ]; then return 1; fi
        echo "Python Cache ($base)"
        return 0
    fi

    # 6. Dart / Flutter
    if [[ "$base" == ".dart_tool" ]]; then
        if [ "$FILTER_TYPE" != "all" ] && [ "$FILTER_TYPE" != "flutter" ]; then return 1; fi
        echo "Dart/Flutter (.dart_tool)"
        return 0
    fi

    # 7. CocoaPods Pods
    if [[ "$base" == "Pods" ]]; then
        local parent
        parent=$(dirname "$p")
        if [ -f "$parent/Podfile" ]; then
            echo "CocoaPods (Pods/)"
            return 0
        fi
        return 1
    fi

    # 8. Gradle
    if [[ "$base" == ".gradle" ]]; then
        if [ "$FILTER_TYPE" != "all" ] && [ "$FILTER_TYPE" != "gradle" ]; then return 1; fi
        echo "Gradle Cache (.gradle)"
        return 0
    fi

    return 1
}

MATCHED_PATHS=()
MATCHED_CATS=()
MATCHED_SIZES=()
MATCHED_KBS=()
TOTAL_KB=0

while IFS= read -r -d '' cand; do
    if category=$(classify_and_validate "$cand"); then
        kb=$(du -sk "$cand" 2>/dev/null | cut -f1 || echo 0)
        hsize=$(du -sh "$cand" 2>/dev/null | cut -f1 || echo "0B")
        MATCHED_PATHS+=("$cand")
        MATCHED_CATS+=("$category")
        MATCHED_SIZES+=("$hsize")
        MATCHED_KBS+=("$kb")
        TOTAL_KB=$((TOTAL_KB + kb))
    fi
done < <(find "${RESOLVED_PATHS[@]}" \
    \( \
        -name ".git" -o \
        -name "Library" -o \
        -name "Applications" -o \
        -name ".cache" -o \
        -name ".config" -o \
        -name ".local" -o \
        -name ".vscode" -o \
        -name ".cargo" -o \
        -name ".rustup" -o \
        -name ".nvm" -o \
        -name ".bun" -o \
        -name ".npm" -o \
        -name ".pyenv" -o \
        -name ".gemini" -o \
        -name ".docker" \
    \) -prune \
    -o -type d \( \
        -name "node_modules" -o \
        -name "target" -o \
        -name ".build" -o \
        -name ".venv" -o \
        -name "venv" -o \
        -name ".virtualenv" -o \
        -name "env" -o \
        -name "__pycache__" -o \
        -name ".pytest_cache" -o \
        -name ".mypy_cache" -o \
        -name ".ruff_cache" -o \
        -name ".next" -o \
        -name ".nuxt" -o \
        -name ".svelte-kit" -o \
        -name ".turbo" -o \
        -name ".parcel-cache" -o \
        -name ".dart_tool" -o \
        -name "Pods" -o \
        -name ".gradle" \
    \) -print0 -prune 2>/dev/null)

COUNT=${#MATCHED_PATHS[@]}

if [ "$COUNT" -eq 0 ]; then
    echo "No matching project artifact folders found in specified paths."
    echo "Everything is already clean!"
    exit 0
fi

TOTAL_STR=$(format_kb "$TOTAL_KB")

echo ""
echo "Discovered Artifacts ($COUNT items, $TOTAL_STR reclaimable):"
echo "----------------------------------------------------------------------"
printf "%-10s  %-26s  %s\n" "SIZE" "CATEGORY" "PATH"
echo "----------------------------------------------------------------------"
for ((i=0; i<COUNT; i++)); do
    printf "%-10s  %-26s  %s\n" "${MATCHED_SIZES[i]}" "${MATCHED_CATS[i]}" "${MATCHED_PATHS[i]}"
done
echo "----------------------------------------------------------------------"
echo "Total Reclaimable Space: $TOTAL_STR across $COUNT directories."
echo ""

if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] No directories were deleted."
    echo "To delete these directories, run without --dry-run."
    exit 0
fi

if [ "$FORCE" = false ]; then
    read -r -p "Permanently delete these $COUNT artifact directories? [y/N]: " CONFIRM
    case "$CONFIRM" in
        [yY]|[yY][eE][sS])
            echo "Proceeding with deletion..."
            ;;
        *)
            echo "Operation aborted by user. No files were deleted."
            exit 0
            ;;
    esac
fi

echo ""
echo "--> Deleting $COUNT artifact directories..."
DELETED_COUNT=0
for ((i=0; i<COUNT; i++)); do
    target_path="${MATCHED_PATHS[i]}"
    echo "[$((i+1))/$COUNT] Deleting: $target_path (${MATCHED_SIZES[i]})"
    rm -rf "$target_path"
    DELETED_COUNT=$((DELETED_COUNT + 1))
done

END_USED_KB=$(df -kP "$PRIMARY_ROOT" | awk 'NR==2 {print $3}')
END_AVAIL_KB=$(df -kP "$PRIMARY_ROOT" | awk 'NR==2 {print $4}')
DIFF_USED_KB=$((START_USED_KB - END_USED_KB))

echo ""
echo "=========================================================="
echo " macOS Project Artifacts Cleanup Complete!"
echo " Deleted:     $DELETED_COUNT directories"
echo " Directory Sum Reclaimed: ~$TOTAL_STR"
echo " Storage Comparison ($PRIMARY_ROOT):"
echo "   Before:    $(format_kb "$START_USED_KB") used, $(format_kb "$START_AVAIL_KB") available"
echo "   After:     $(format_kb "$END_USED_KB") used, $(format_kb "$END_AVAIL_KB") available"
if [ "$DIFF_USED_KB" -gt 0 ]; then
    echo "   Reclaimed: $(format_kb "$DIFF_USED_KB")"
else
    echo "   Reclaimed: ~$TOTAL_STR"
fi
echo " Note: You can redownload or regenerate packages anytime"
echo " (e.g. npm install, cargo build, swift build, python -m venv .venv)."
echo "=========================================================="
