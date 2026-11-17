# Linux Developer Disk Cleanup

Audit commands and automation scripts to reclaim 20–50 GB of compiler caches, build artifacts, container storage, and system logs on Linux workstations without touching source code or personal data.

---

## Table of Contents

- [Overview](#overview)
- [Script Quick Reference (SCRIPTS.md)](SCRIPTS.md)
- [Diagnostic Baseline](#diagnostic-baseline)
- [Automated Scripts](#automated-scripts)
  - [1. Project Artifacts (`cleanup_artifacts.sh`)](#1-project-artifacts-cleanup_artifactssh)
  - [2. Zero-Docker Toolchains (`cleanup_no_docker.sh`)](#2-zero-docker-toolchains-cleanup_no_dockersh)
  - [3. Docker Storage (`cleanup_docker.sh` & `cleanup_docker_unused.sh`)](#3-docker-storage-cleanup_dockersh--cleanup_docker_unusedsh)
  - [4. Legacy Single-Scope Scripts](#4-legacy-single-scope-scripts)
- [Manual Cleanup Reference](#manual-cleanup-reference)
  - [Phase 1: Safe Toolchain & Package Caches](#phase-1-safe-toolchain--package-caches)
  - [Phase 2: Project Build Artifacts](#phase-2-project-build-artifacts)
  - [Phase 3: Workloads & Virtual Environments](#phase-3-workloads--virtual-environments)
- [Protected Paths](#protected-paths)
- [Operational Guidelines](#operational-guidelines)

---

## Overview

Linux development workstations accumulate regenerable files across package managers, compilers, container runtimes, and editors. Common targets and their typical reclaimable footprints include:

| Component | Target Locations | Typical Reclaim |
|---|---|---|
| **Build Artifacts** | `node_modules`, `target/`, `.venv`, `__pycache__` | 5–25 GB |
| **Containers** | Docker BuildKit cache, stopped containers, dangling images | 5–20 GB |
| **Package Caches** | `~/.cache/pip`, `~/.bun/install/cache`, `npm`, APT archives | 3–10 GB |
| **Compilers & IDEs** | Go build cache, Cargo checkouts, VS Code C++ IPCH / VSIXs | 2–8 GB |
| **System Journals** | `/var/log/journal/`, `/var/crash/`, disabled snaps | 2–6 GB |

---

## Diagnostic Baseline

Run these read-only commands before cleaning to identify where storage is consumed:

```bash
# 1. Check root filesystem capacity and mount points
df -hT /

# 2. Check inode consumption (prevent inode exhaustion)
df -i /

# 3. List largest top-level directories on root
du -hx --max-depth=1 / 2>/dev/null | sort -hr | head -n 10

# 4. List largest directories in user home
du -hx --max-depth=1 "$HOME" 2>/dev/null | sort -hr | head -n 10

# 5. Check unlinked open files held by running processes
lsof +L1 2>/dev/null | grep -vE 'memfd|/dev/shm'

# 6. Check systemd journal storage
journalctl --disk-usage

# 7. Check Docker engine disk allocation (if Docker is running)
docker system df
```

---

## Automated Scripts

The repository provides standalone scripts tailored for **Linux** (repository root), **macOS** ([`mac/`](mac/)), and **Windows** ([`windows/`](windows/)). For the cross-platform command matrix and criticality ratings, see [`SCRIPTS.md`](SCRIPTS.md).

- **Linux:** Native Bash scripts in root (`./cleanup_*.sh`)
- **macOS:** Native Bash scripts in `mac/` (`./mac/cleanup_*.sh`) using `~/Library/Caches/`, Xcode `DerivedData`, and Homebrew
- **Windows:** Native PowerShell scripts in `windows/` (`.\windows\cleanup_*.ps1`) using `%LOCALAPPDATA%`, `%APPDATA%`, and Windows Update stores

### 1. Project Artifacts (`cleanup_artifacts.sh`)

Scans repositories and workspaces for regenerable language dependencies and build caches.

- **Targets:** `node_modules`, `.next`, `.turbo`, Rust `target/`, Python `.venv`/`venv`, `__pycache__`, `.pytest_cache`, `.dart_tool`, and `.gradle`.
- **Safety checks:** Verifies virtual environments contain `pyvenv.cfg` or `bin/activate` before deletion (never removes `.env` configuration files). Verifies `target/` directories contain `Cargo.toml`, `pom.xml`, or `CACHEDIR.TAG`.
- **Exclusions:** Automatically prunes `.git`, `.vscode`, `.cargo`, `.rustup`, `.nvm`, and system paths from discovery.
- **Default behavior:** Scans detected project directories (`~/coding`, `~/projects`, `~/open_source`, `~/eval`, `~/ai`) or current directory `.`. Displays an itemized table with sizes and prompts for confirmation (`[y/N]`).

```bash
# Preview matching folders and total reclaimable space
./cleanup_artifacts.sh --dry-run

# Interactive run across detected project folders
./cleanup_artifacts.sh

# Scan a specific directory
./cleanup_artifacts.sh ~/coding

# Filter by language ecosystem
./cleanup_artifacts.sh --dry-run --node    # node_modules and frontend caches
./cleanup_artifacts.sh --dry-run --rust    # Rust target/ directories
./cleanup_artifacts.sh --dry-run --python  # Python .venv, venv, and __pycache__

# Force execution without interactive prompt
./cleanup_artifacts.sh -f ~/coding
```

*(Also accessible via symlink: `./cleanup_project_artifacts.sh`)*

---

### 2. Zero-Docker Toolchains (`cleanup_no_docker.sh`)

Cleans user-space package manager caches, IDE caches, compiler artifacts, and browser caches with a **strict guarantee that Docker is never accessed**.

- **Targets:**
  - **Python:** `~/.cache/pip` (`pip cache purge`), `~/.cache/uv` (`uv cache clean`).
  - **JavaScript / Node:** `~/.bun/install/cache`, NPM cache (`npm cache clean --force`), Yarn cache, and pnpm store prune.
  - **Rust / Cargo:** `~/.cargo/git/checkouts`, `~/.cargo/git/db`, `.package-cache`.
  - **Go:** `go clean -cache -testcache` (and `go clean -modcache` with `--deep`).
  - **C/C++:** `ccache -C`, Clangd language server cache.
  - **IDEs:** VS Code C++ precompiled headers (`ipch`) and cached `.vsix` extension installers.
  - **Browsers:** HTTP disk caches for Brave, Google Chrome, Chromium, and Firefox (preserves logins, cookies, history, and bookmarks).
  - **Stray Packages:** Leftover `.deb` files in `~/Downloads`.
- **System caches (optional):** When executed with `sudo` or `-s/--system`, cleans APT archives (`apt-get clean`, `autoremove`), systemd journals (`--vacuum-size=200M`), disabled snap revisions, and `/var/crash/`.

```bash
# Standard user-level cleanup (no sudo needed, Docker untouched)
./cleanup_no_docker.sh

# Preview actions and cache sizes without deleting
./cleanup_no_docker.sh --dry-run

# Include system-level cleanup (requires sudo)
sudo ./cleanup_no_docker.sh -s

# Deep clean (also cleans Go module cache and unpacked Cargo crate sources)
./cleanup_no_docker.sh -d
```

---

### 3. Docker Storage (`cleanup_docker.sh` & `cleanup_docker_unused.sh`)

Exclusively manages Docker resources. Does not touch host files, local project code, or non-Docker caches.

#### Standard Docker Cleanup (`cleanup_docker.sh`)
- **Pre-flight check:** Verifies Docker CLI availability and active daemon connectivity before running.
- **Default behavior (Safe Prune):**
  - Prunes stopped containers (`docker container prune -f`).
  - Prunes dangling images `<none>:<none>` (`docker image prune -f`).
  - Prunes expired BuildKit build cache (`docker builder prune -f`).
  - Prunes unused custom networks (`docker network prune -f`).
  - Cleans rotated Docker Desktop log files in `~/.docker/desktop/log`.
- **Preserves:** Running containers, tagged images, and mounted volumes are preserved by default.

```bash
# Preview reclaimable Docker storage without modifying anything
./cleanup_docker.sh --dry-run

# Safe prune (stopped containers, dangling images, untagged build cache)
./cleanup_docker.sh

# Deep prune: remove all unused images and complete builder cache
./cleanup_docker.sh --all

# Include unused volume cleanup (deletes unmounted persistent volumes)
./cleanup_docker.sh --volumes

# Combined deep prune with volumes
./cleanup_docker.sh -a -v
```

#### Purge All Unused Docker Data (`cleanup_docker_unused.sh`)
Purges everything not currently active. Removes all stopped containers, all unreferenced images, all unattached volumes, all unused networks, and all builder cache in one pass. Running containers, active images, and attached volumes remain intact.

```bash
# Preview inactive containers, images, and volumes to be purged
./cleanup_docker_unused.sh --dry-run

# Interactive purge (prompts before deleting unattached volumes/images)
./cleanup_docker_unused.sh

# Force purge without confirmation prompt
./cleanup_docker_unused.sh -f
```

---

### 4. Legacy Single-Scope Scripts

- **`cleanup_user.sh`:** Legacy user-space cleanup script for package caches, Go build cache, and VS Code headers.
- **`cleanup_system.sh`:** Legacy system-space script for APT archives, journal vacuuming, and snap revisions (requires `sudo`).

---

## Manual Cleanup Reference

### Phase 1: Safe Toolchain & Package Caches

Zero data risk. All targets regenerate automatically on demand.

| Component | Target Location | Command | Notes |
|---|---|---|---|
| **APT Archive** | `/var/cache/apt/archives` | `sudo apt-get clean` | Deletes downloaded `.deb` installer packages. |
| **Systemd Journals** | `/var/log/journal` | `sudo journalctl --vacuum-size=200M` | Caps retained journal log size to 200 MB. |
| **Disabled Snaps** | `/var/lib/snapd/snaps` | `snap list --all \| awk '/disabled/{print $1, $3}' \| while read n r; do sudo snap remove "$n" --revision="$r"; done` | Removes inactive historical snap revisions. |
| **Pip Cache** | `~/.cache/pip` | `rm -rf ~/.cache/pip` or `pip cache purge` | Wheel archive cache; installed packages are unaffected. |
| **UV Cache** | `~/.cache/uv` | `uv cache clean` | Re-downloads wheels on next install. |
| **Bun Cache** | `~/.bun/install/cache` | `rm -rf ~/.bun/install/cache/*` | Re-downloads packages on `bun install`. |
| **NPM Global Cache** | `~/.npm/_cacache` | `npm cache clean --force` | Re-downloaded as needed. |
| **Go Build Cache** | `~/.cache/go-build` | `go clean -cache -testcache` | Recompiled on next `go build`. |
| **VS Code C++ IPCH** | `~/.cache/vscode-cpptools/ipch` | `rm -rf ~/.cache/vscode-cpptools/ipch/*` | IntelliSense precompiled headers; rebuilt while editing. |
| **VS Code VSIXs** | `~/.config/Code/CachedExtensionVSIXs` | `rm -rf ~/.config/Code/CachedExtensionVSIXs/*` | Staged installer files; installed extensions remain intact. |
| **Crash Reports** | `/var/crash` | `sudo rm -f /var/crash/*.crash` | Historical crash dumps. |

---

### Phase 2: Project Build Artifacts

Safe to remove. Source code, git branches, and commit histories are untouched. Next build compiles from scratch.

| Component | Target Location | Command | Notes |
|---|---|---|---|
| **Rust Project Targets** | `<project>/target` | `cargo clean` | Frees 1–10+ GB per dormant repo. Rebuilt with `cargo build`. |
| **Cargo Checkouts** | `~/.cargo/git/checkouts` | `rm -rf ~/.cargo/git/checkouts/*` | Cloned git dependency repositories; re-fetched during build. |
| **Go Module Cache** | `~/go/pkg/mod` | `go clean -modcache` | Re-downloaded during `go build` or `go mod download`. |

---

### Phase 3: Workloads & Virtual Environments

Review active usage before deletion.

| Component | Target Location | Command | Notes |
|---|---|---|---|
| **Node Modules** | `<project>/node_modules` | `rm -rf /path/to/project/node_modules` | Reinstall with `npm install`, `pnpm install`, or `bun install`. |
| **Python VirtualEnvs** | `<project>/.venv` | `rm -rf /path/to/project/.venv` | Recreate with `python3 -m venv .venv && pip install -r requirements.txt`. |
| **Docker Desktop VM Disk** | `~/.docker/desktop` | `rm -rf ~/.docker/desktop` | Verify no needed database volumes exist before removing the VM disk file (`Docker.raw`). |
| **Browser Web Cache** | `~/.cache/google-chrome/` | `rm -rf ~/.cache/google-chrome/Default/Cache/*` | HTTP cache only; logins, passwords, and bookmarks are untouched. |

---

## Protected Paths

The scripts explicitly exclude these locations to prevent data loss or system corruption:

- **Virtual memory:** Swap files (`/swap.img`).
- **Kernels:** Running kernel (`uname -r`) and immediate fallback kernel images (`vmlinuz.old`).
- **Repositories:** Git configuration and history directories (`.git/`).
- **Secrets & credentials:** `~/.ssh/`, `~/.gnupg/`, `~/.sigstore/`, and `.env` configuration files.
- **User profiles & settings:** `~/.config/Code/User/`, `~/.config/nvim/`, browser profile databases (`Login Data`, `Bookmarks`).
- **User documents:** `~/Documents/`, personal pictures, and videos.

---

## Operational Guidelines

1. **Measure before and after:** Run `df -hT /` or `df -h "$HOME"` before executing cleanups.
2. **Release open file handles:** If disk space does not release after deletion, run `lsof +L1` to verify if running background processes still hold deleted file descriptors open.
3. **Preserve one fallback kernel:** Never purge the running kernel or the previous fallback kernel during package autoremoval.
