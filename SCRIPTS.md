# Script & File Reference

Direct map of each file in this repository to its target, permission model, Docker behavior, recovery criticality score, and command options across Linux, macOS, and Windows.

---

## Criticality & Recovery Score (1 to 5)

Scores evaluate how quickly and easily deleted items can be restored:

| Score | Rating | Recovery Effort & Impact | Example |
|:---:|---|---|---|
| **1** | **Trivial** | Restores automatically on next run or build. Zero thinking, zero risk. Takes seconds. | Go build cache, browser HTTP cache, VS Code C++ IPCH, `__pycache__`, Rust `target/`. |
| **2** | **Minor Friction** | Restores via standard manifest install commands (`npm install`, `pip install -r requirements.txt`). Takes 1–5 minutes and network bandwidth. | Project `node_modules`, Python `.venv`, Cargo git checkouts, APT/Homebrew archive cache. |
| **3** | **Moderate Friction** | Irreversible local data loss if unattached volumes held uncommitted test database state. Re-pulling images takes bandwidth. | Unattached Docker volumes, deleted stopped containers, all unused container images. |
| **4** | **High Friction** | Manual reconfiguration required; takes hours of troubleshooting. *(Excluded by all scripts).* | Deleting uncommitted project files, active virtualenv without a requirements file. |
| **5** | **Catastrophic** | System or repository disaster. Takes hours to days to repair. *(Strictly protected by all scripts).* | Deleting `.git/` history, swap files, running kernels, SSH keys (`~/.ssh`), or registry/glibc. |

---

## Platform Matrix (Linux, macOS, Windows)

| Script Purpose | Criticality | Linux (Root) | macOS (`mac/`) | Windows (`windows/`) |
|---|:---:|---|---|---|
| **Project Artifacts** (`node_modules`, `target`, `.venv`) | **2** | `./cleanup_artifacts.sh` | `./mac/cleanup_artifacts.sh` | `.\windows\cleanup_artifacts.ps1` |
| **Zero-Docker Toolchains** (caches, IDEs, browsers) | **1** *(User)*<br>**2** *(System)* | `./cleanup_no_docker.sh` | `./mac/cleanup_no_docker.sh` | `.\windows\cleanup_no_docker.ps1` |
| **Docker Safe Prune** (stopped, dangling, build cache) | **1** *(Safe)*<br>**3** *(Volumes)* | `./cleanup_docker.sh` | `./mac/cleanup_docker.sh` | `.\windows\cleanup_docker.ps1` |
| **Docker Purge All Unused** (all unused images, volumes) | **3** | `./cleanup_docker_unused.sh` | `./mac/cleanup_docker_unused.sh` | `.\windows\cleanup_docker_unused.ps1` |
| **User Space Only** (legacy user-level caches) | **1** | `./cleanup_user.sh` | `./mac/cleanup_user.sh` | `.\windows\cleanup_user.ps1` |
| **System Space Only** (journals/Homebrew/WinUpdate) | **2** | `sudo ./cleanup_system.sh` | `sudo ./mac/cleanup_system.sh` | `.\windows\cleanup_system.ps1` *(Admin)* |

---

## Script Matrix Details

| File | Criticality | Target Scope | Privileges | Docker Impact | Description | Key Flags |
|---|:---:|---|---|---|---|---|
| [`scan_disk.sh`](scan_disk.sh) | **1** *(Safe)* | Whole system & user home | User (Root optional) | Read-Only Inspection | 100% read-only diagnostic scanner and disk usage audit. Scans filesystems, Docker VM disks, Snaps, browser caches, dev toolchains, and largest files without deleting anything. | `-d` (deep)<br>`-t` (threshold)<br>`--home-only`<br>`-h` (help) |
| [`cleanup_artifacts.sh`](cleanup_artifacts.sh) | **2** | Project workspaces (`~/coding`, etc.) | User | None (Untouched) | Deletes local dependencies and build outputs (`node_modules`, `target/`, `.venv`, `__pycache__`, `.turbo`, `.gradle`). Re-create with `npm install` or `pip install -r requirements.txt`. | `-n` (dry-run)<br>`-f` (force)<br>`--node`<br>`--rust`<br>`--python` |
| [`cleanup_project_artifacts.sh`](cleanup_project_artifacts.sh) | **2** | Project workspaces | User | None (Untouched) | Symlink pointing to `cleanup_artifacts.sh`. Same behavior and recovery as target script. | Same as `cleanup_artifacts.sh` |
| [`cleanup_no_docker.sh`](cleanup_no_docker.sh) | **1** *(User)*<br>**2** *(System)* | Toolchains, IDEs, browsers, system logs | User (Root optional) | None (Strictly excluded) | Cleans Pip, UV, Bun, NPM, Yarn, pnpm, Go, Cargo, ccache, VS Code C++ IPCH, browser HTTP caches, and `.deb` packages. With `-s`, cleans APT and journalctl. | `-n` (dry-run)<br>`-s` (system)<br>`-d` (deep)<br>`-h` (help) |
| [`cleanup_docker.sh`](cleanup_docker.sh) | **1** *(Safe)*<br>**3** *(Volumes)* | Docker daemon storage | User / Docker group | Targets Docker only | Safe default prune for stopped containers, dangling images (`<none>`), untagged build cache, and unused networks. With `-v`, also prunes unattached volumes (Score 3). | `-n` (dry-run)<br>`-a` (all images)<br>`-v` (volumes)<br>`-h` (help) |
| [`cleanup_docker_unused.sh`](cleanup_docker_unused.sh) | **3** | Docker daemon storage | User / Docker group | Targets Docker only | Purges ALL stopped containers, unused images, unattached volumes, and builder cache. Running containers remain untouched, but data in unattached volumes cannot be restored without backups. | `-n` (dry-run)<br>`-f` (force)<br>`-h` (help) |
| [`cleanup_user.sh`](cleanup_user.sh) | **1** | User home (`$HOME`) | User | None (Untouched) | Reclaims pure user-space caches (VS Code IPCH/VSIXs, Pip wheel cache, Bun cache, NPM cache, Go build cache, browser caches, and `~/Downloads/*.deb`). | None |
| [`cleanup_system.sh`](cleanup_system.sh) | **2** | Root filesystem (`/`) | Root (`sudo`) | None (Untouched) | Vacuums journalctl to 200 MB, purges APT cache and orphaned packages, removes disabled snaps, clears `/var/crash`. Active kernel and fallback kernel are preserved. | Requires `sudo` |

---

## macOS Scripts (`mac/`)

Tailored for macOS paths (`~/Library/Caches/`, Xcode DerivedData, Homebrew, Apple crash reports):

- **`mac/cleanup_user.sh`:** Cleans VS Code caches, Pip/UV, Bun, NPM, Go, Xcode `DerivedData`, Chrome/Brave/Safari caches, and `~/Downloads/*.dmg`, `*.pkg`.
- **`mac/cleanup_system.sh`:** Cleans Homebrew cache (`brew cleanup -s`, `brew autoremove`), system diagnostic reports in `/Library/Logs/DiagnosticReports`, `/Library/Caches`, and flushes DNS.
- **`mac/cleanup_no_docker.sh`:** Complete non-Docker cleanup covering toolchains, Xcode, browsers, and optional Homebrew system cleanup (`-s`).
- **`mac/cleanup_docker.sh`:** Prunes Docker Desktop for Mac containers, dangling images, build cache, and rotated logs in `~/Library/Containers/com.docker.docker/Data/log`.
- **`mac/cleanup_docker_unused.sh`:** Purges all stopped containers, unused images, unattached volumes, and BuildKit cache on macOS.
- **`mac/cleanup_artifacts.sh`:** Scans for `node_modules`, Rust `target/`, Swift Package Manager `.build/`, CocoaPods `Pods/`, `.venv`, and `__pycache__` while strictly excluding `~/Library` and `/Applications`.

---

## Windows Scripts (`windows/`)

PowerShell scripts (`.ps1`) targeting `%LOCALAPPDATA%`, `%APPDATA%`, `%TEMP%`, and Windows Update stores:

- **`windows\cleanup_user.ps1`:** Cleans VS Code IPCH/VSIXs, Pip/UV caches, Bun, NPM, Go, Chrome/Brave/Edge web caches, and user `%TEMP%`.
- **`windows\cleanup_system.ps1`:** Requires Run as Administrator. Cleans Windows Update `SoftwareDistribution\Download`, System Temp `C:\Windows\Temp`, WER crash archives, WinGet/Chocolatey/Scoop caches, and empties the Recycle Bin.
- **`windows\cleanup_no_docker.ps1`:** Complete non-Docker cleanup supporting `-DryRun`, `-Deep`, and `-System`. WSL2 and Docker Desktop disks are strictly excluded.
- **`windows\cleanup_docker.ps1`:** Safe Docker prune on Windows with `-All`, `-Volumes`, and `-DryRun` support.
- **`windows\cleanup_docker_unused.ps1`:** Full purge of inactive containers, images, volumes, and build cache on Windows.
- **`windows\cleanup_artifacts.ps1`:** Scans for `node_modules`, Rust `target/`, .NET `bin/`/`obj/`, Python `.venv`, `__pycache__`, and `.gradle` while excluding `AppData`, `Program Files`, and `Windows`.

---

## Non-Executable Repository Files

| File | Criticality | Purpose |
|---|:---:|---|
| [`README.md`](README.md) | **1** | Primary documentation, baseline diagnostics, manual commands, protected paths, and operational guidelines. |
| [`SCRIPTS.md`](SCRIPTS.md) | **1** | Script reference, platform matrix, criticality ratings, and execution cheat sheet (this document). |
| [`.gitignore`](.gitignore) | **1** | Excludes editor state, local logs, and temporary files from git tracking. |
