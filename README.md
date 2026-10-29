# Linux Disk Space Cleanup & Forensics Guide 🚀

A comprehensive, production-tested audit guide and toolkit for Linux software engineers, systems administrators, and coding assistants to systematically identify, classify, and safely reclaim 20–50+ GB of disk space from developer workstations.

---

## 📌 Table of Contents

- [Overview](#overview)
- [Diagnostic Baseline Commands](#diagnostic-baseline-commands)
- [Master Action Matrix](#master-action-matrix)
  - [Phase 1: Safe System & Toolchain Caches](#phase-1-safe-system--toolchain-caches-zero-user-data-risk)
  - [Phase 2: Project Build Artifacts](#phase-2-project-build-artifacts-safe-source-code-untouched)
  - [Phase 3: Inactive Workloads & Environments](#phase-3-inactive-workloads--environments-review-needed)
- [Protected Data Checklist](#protected-data-checklist-never-delete-these)
- [Automated Scripts](#automated-scripts)
  - [User-Level Cleanup (`cleanup_user.sh`)](#1-user-level-cleanup-cleanup_usersh)
  - [System-Level Cleanup (`cleanup_system.sh`)](#2-system-level-cleanup-cleanup_systemsh)
- [Contributing & Best Practices](#contributing--best-practices)

---

## Overview

Software development on Linux accumulates hidden disk bloat across compilers, package managers, IDE extensions, container engines, and AI models. A typical workstation often harbors **25 to 45 GB** of obsolete, regenerable files:

1. **Compilers & Toolchains:** Rust duplicate toolchains (`rustup`), Go build cache, C/C++ precompiled headers (`ipch`).
2. **Package Manager Caches:** `pip`, `bun`, `npm`, `apt`.
3. **IDE Internals:** VS Code cached `.vsix` extension installers and stale language-server caches.
4. **Build Artifacts:** Massive `target/` (Rust), `.venv` (Python), and `node_modules` directories in dormant projects.
5. **Snap Storage:** Inactive, superseded versions of installed snap applications kept on disk.
6. **Container & VM Storage:** Inactive Docker Desktop sparse VM virtual disks (`Docker.raw`).
7. **System Journals & Kernels:** Uncapped systemd journals and old superseded Linux kernel headers.

---

## Diagnostic Baseline Commands

Before running any cleanup, run these read-only diagnostics to establish where space is consumed:

```bash
# 1. Check filesystem capacity and available space
df -hT /

# 2. Check inode utilization (prevent inode exhaustion)
df -i /

# 3. Measure top-level directory usage on root filesystem
du -hx --max-depth=1 / 2>/dev/null | sort -hr

# 4. Measure top-level directories in your user home
du -hx --max-depth=1 "$HOME" 2>/dev/null | sort -hr

# 5. Check for deleted unlinked files held open by running processes
lsof +L1 2>/dev/null | grep -v 'memfd' | grep -v '/dev/shm'

# 6. Check systemd journal disk consumption
journalctl --disk-usage

# 7. Check for inactive/disabled Snap package revisions
snap list --all | grep disabled
```

---

## Master Action Matrix

### Phase 1: Safe System & Toolchain Caches (Zero User Data Risk)

These targets consist entirely of redundant compiler binaries, system package caches, old log files, and automatic precompiled headers.

| Target / Component | Typical Reclaim | Cleanup Type | Recommended Command | Risk |
|---|---:|---|---|---|
| **Duplicate Rust Toolchains** | 1.0 – 2.0 GB | Dedicated CLI | `rustup toolchain list` <br> `rustup toolchain uninstall <duplicate-toolchain>` | **Zero.** Active default toolchain remains intact. |
| **Disabled Snap Revisions** | 2.0 – 5.0 GB | Dedicated CLI (`sudo`) | `snap list --all \| awk '/disabled/{print $1, $3}' \| while read name rev; do sudo snap remove "$name" --revision="$rev"; done` | **Zero.** Active snap versions remain running. |
| **Systemd Journal Logs** | 1.0 – 4.0 GB | Dedicated CLI (`sudo`) | `sudo journalctl --vacuum-size=200M` | **Low.** Retains the most recent 200 MB of system logs. |
| **APT Package Archive Cache** | 400 MB – 2 GB | Dedicated CLI (`sudo`) | `sudo apt-get clean` | **Zero.** Clears downloaded `.deb` installer cache in `/var/cache/apt/archives`. |
| **Orphaned / Old Kernels** | 500 MB – 2 GB | Dedicated CLI (`sudo`) | `sudo apt purge -y linux-headers-<old-version>* linux-image-<old-version>-generic` | **Zero.** Active and fallback kernels are retained. |
| **VS Code C++ Precompiled Headers** | 500 MB – 3 GB | Filesystem `rm` | `rm -rf ~/.cache/vscode-cpptools/ipch/*` | **Zero.** Regenerated automatically by IntelliSense when editing C++. |
| **Pip HTTP Download Cache** | 1.0 – 5.0 GB | Filesystem `rm` | `rm -rf ~/.cache/pip` | **Zero.** Pure wheel archive cache; installed packages are unaffected. |
| **Bun Package Cache** | 500 MB – 2 GB | Filesystem `rm` | `rm -rf ~/.bun/install/cache/*` | **Zero.** Redownloaded automatically on `bun install`. |
| **NPM Global Cache** | 300 MB – 1 GB | Dedicated CLI | `npm cache clean --force` | **Zero.** Re-downloaded as needed. |
| **Go Compiler Build Cache** | 200 MB – 1 GB | Dedicated CLI | `go clean -cache` | **Zero.** Packages recompile automatically on next `go build`. |
| **VS Code Cached VSIX Installers** | 200 MB – 1 GB | Filesystem `rm` | `rm -rf ~/.config/Code/CachedExtensionVSIXs/*` | **Zero.** Extensions are already installed and unpacked. |
| **Downloaded `.deb` Installers** | 200 MB – 2 GB | Filesystem `rm` | `rm -f ~/Downloads/*.deb` | **Zero.** Packages are already installed on the system. |
| **Application Crash Reports** | 50 MB – 500 MB | Filesystem `rm` (`sudo`) | `sudo rm -f /var/crash/*.crash` | **Zero.** Informational crash dumps. |

---

### Phase 2: Project Build Artifacts (Safe, Source Code Untouched)

Cleaning build artifacts does not touch git commit history, branches, or source code. Next compilation builds from scratch.

| Target | Typical Reclaim | Cleanup Type | Recommended Command | Risk |
|---|---:|---|---|---|
| **Rust Project `target/` Dirs** | 1.0 – 10.0+ GB per repo | Dedicated CLI | `cargo clean` *(inside repo root)* | **Zero to code.** Rebuild takes CPU time. |
| **Go Module Cache** | 300 MB – 2 GB | Dedicated CLI | `go clean -modcache` | **Zero to code.** Modules redownloaded on build. |
| **Cargo Registry Caches** | 500 MB – 2 GB | Filesystem `rm` | `rm -rf ~/.cargo/registry/src/*` | **Zero to code.** Crates re-extracted on build. |

---

### Phase 3: Inactive Workloads & Environments (Review Needed)

Verify that these workloads are truly dormant before removing.

| Target | Typical Reclaim | Cleanup Type | Recommended Command | Considerations |
|---|---:|---|---|---|
| **Docker Desktop VM Disk** | 3.0 – 20.0+ GB | Filesystem `rm` | `rm -rf ~/.docker/desktop` | Verify no persistent database volumes exist inside Docker Desktop VM before removing. |
| **Inactive Python `.venv` Folders** | 300 MB – 2 GB per env | Filesystem `rm` | `rm -rf /path/to/dormant_project/.venv` | Ensure `requirements.txt` or `pyproject.toml` exists to recreate environment. |
| **Inactive Project `node_modules`** | 300 MB – 1.5 GB per repo | Filesystem `rm` | `rm -rf /path/to/dormant_project/node_modules` | Reinstallable with `npm install` or `bun install`. |
| **Cached Hugging Face Model Weights** | 2.0 – 20.0+ GB | Filesystem `rm` | `rm -rf ~/.cache/huggingface/hub/models--<model-name>` | Re-downloading large AI models requires network bandwidth. |
| **Browser Web & Shader Caches** | 1.0 – 3.0 GB | Filesystem `rm` | `rm -rf ~/.cache/google-chrome/Default/Cache/* ~/.cache/BraveSoftware/Brave-Browser/Default/Cache/*` | Web pages re-cache automatically on visit. Passwords/history untouched. |

---

## Protected Data Checklist (Never Delete These)

When writing automated cleanup routines, ensure these paths are strictly excluded:

- ❌ **Swap File (`/swap.img`):** System virtual memory allocation.
- ❌ **Current Kernel & Immediate Fallback:** Active running kernel and `vmlinuz.old` / `initrd.img.old`.
- ❌ **User Source Code & Git Repositories:** All uncommitted changes and `.git/` directories.
- ❌ **IDE Settings & Profiles:** `~/.config/Code/User`, `~/.config/nvim`, personal snippets, and keybindings.
- ❌ **Browser Profiles:** Bookmarks, saved credentials, cookies (`Default/Login Data`, `Default/Bookmarks`).
- ❌ **Authentication Keys & Secrets:** `~/.ssh`, `~/.gnupg`, `~/.sigstore`.
- ❌ **User Media & Documents:** `~/Documents`, `~/Videos/Screencasts`, personal photos.

---

## Automated Scripts

Two turnkey scripts are included in this repository:

### 1. User-Level Cleanup (`cleanup_user.sh`)
Safe to run without root privileges. Cleans user-space package caches, language build caches, precompiled headers, and cached extension packages:

```bash
chmod +x cleanup_user.sh
./cleanup_user.sh
```

### 2. System-Level Cleanup (`cleanup_system.sh`)
Cleans systemd journal archives, old snap versions, APT archives, and old kernel packages. Requires `sudo`:

```bash
chmod +x cleanup_system.sh
./cleanup_system.sh
```

---

## Contributing & Best Practices

1. **Always measure before and after:** Run `df -hT /` before starting.
2. **Never force-kill processes to delete open files:** Check `lsof +L1` to ensure running services release locks naturally.
3. **Keep one fallback kernel:** When purging old Linux kernels, never remove the current running kernel (`uname -r`) or the immediate previous fallback kernel.
4. **Use generic `$HOME` paths:** Avoid hardcoding specific usernames when sharing scripts.
