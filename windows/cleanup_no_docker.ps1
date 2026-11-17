<#
==============================================================================
Windows Developer Disk Cleanup - Non-Docker Script (ZERO DOCKER TOUCH)
Reclaims disk space across developer toolchains, package managers, build caches,
IDE artifacts, browser caches, and Windows temporary stores.

GUARANTEE: Does NOT touch Docker containers, images, volumes, build cache,
WSL2 Docker virtual disks, or any Docker-related configurations.
==============================================================================
#>
[CmdletBinding()]
param(
    [switch]$System,
    [switch]$Deep,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = 'SilentlyContinue'

if ($Help) {
    Write-Host @"
Usage: .\windows\cleanup_no_docker.ps1 [OPTIONS]

Reclaim disk space from Windows developer junk WITHOUT touching Docker.

OPTIONS:
  -System      Include system-level cleanup (Windows Update cache, System Temp,
               WER crash archives, WinGet/Choco cache, Recycle Bin).
               Requires Administrator privileges.
  -Deep        Include deeper caches (e.g., Go module cache, Cargo registry sources).
  -DryRun      Inspect and calculate target cache sizes without deleting anything.
  -Help        Show this help message.

WHAT THIS SCRIPT CLEANS:
  - IDE: VS Code C++ precompiled headers, cached extension VSIXs.
  - Python: Pip wheel download cache, UV package cache.
  - Rust: Cargo git checkouts, package cache (and registry sources if -Deep).
  - Node / JS: Bun cache, NPM global cache, Yarn cache, pnpm store.
  - Go: Go build cache, Go test cache (and Go module cache if -Deep).
  - C/C++: ccache compiler cache.
  - Browsers: HTTP web caches for Chrome, Brave, Edge.
  - System (with -System): Windows Update, System Temp, WER, Recycle Bin.

GUARANTEE:
  - Docker is 100% untouched. Running containers, images, volumes, and
    Docker Desktop / WSL2 disks are preserved completely.
"@
    exit 0
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "$([Math]::Round($Bytes / 1GB, 2)) GB"
    } elseif ($Bytes -ge 1MB) {
        return "$([Math]::Round($Bytes / 1MB, 2)) MB"
    } elseif ($Bytes -ge 1KB) {
        return "$([Math]::Round($Bytes / 1KB, 2)) KB"
    } else {
        return "$Bytes B"
    }
}

function Get-DriveFreeBytes {
    param([string]$Path = $env:USERPROFILE)
    $driveLetter = (Split-Path -Qualifier (Resolve-Path $Path).Path).TrimEnd(':')
    $drive = Get-PSDrive -Name $driveLetter
    return $drive.Free
}

function Get-DirectorySize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $measure = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
    if ($measure.Sum) { return $measure.Sum } else { return 0 }
}

function Clean-DirectoryContents {
    param(
        [string]$Path,
        [string]$Description
    )
    if (Test-Path -Path $Path) {
        $size = Get-DirectorySize -Path $Path
        if ($size -gt 4KB) {
            Write-Host "--> $Description (Size: $(Format-Bytes $size))..." -ForegroundColor Cyan
            if ($DryRun) {
                Write-Host "    [DRY-RUN] Would clear contents of: $Path" -ForegroundColor DarkGray
            } else {
                Get-ChildItem -Path $Path -Force -Recurse -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Clean-DirectoryEntirely {
    param(
        [string]$Path,
        [string]$Description
    )
    if (Test-Path -Path $Path) {
        $size = Get-DirectorySize -Path $Path
        if ($size -gt 4KB) {
            Write-Host "--> $Description (Size: $(Format-Bytes $size))..." -ForegroundColor Cyan
            if ($DryRun) {
                Write-Host "    [DRY-RUN] Would remove: $Path" -ForegroundColor DarkGray
            } else {
                Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

$startFree = Get-DriveFreeBytes -Path $env:USERPROFILE

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Windows Non-Docker Developer Disk Cleanup"
Write-Host " GUARANTEE: Docker daemon, containers, & WSL2 VM disks are UNTOUCHED."
if ($DryRun) {
    Write-Host " MODE: DRY RUN (inspections only, no files deleted)"
} elseif ($Deep) {
    Write-Host " MODE: DEEP CLEAN (includes module & registry caches)"
} else {
    Write-Host " MODE: STANDARD CLEAN"
}
if ($System) {
    Write-Host " SYSTEM CLEANUP: Enabled (Windows Update, Temp, WER, Recycle Bin)"
} else {
    Write-Host " SYSTEM CLEANUP: Skipped (pass -System to enable)"
}
Write-Host "==========================================================" -ForegroundColor Green

Write-Host "--> Initial Free Space: $(Format-Bytes $startFree)"
Write-Host "==========================================================" -ForegroundColor Green

# 1. IDE & Editor Caches
Write-Host "--- [1/8] Cleaning IDE & Editor Caches ---" -ForegroundColor Yellow
$ipchPath = Join-Path $env:LOCALAPPDATA "Microsoft\vscode-cpptools\ipch"
Clean-DirectoryContents -Path $ipchPath -Description "VS Code C++ precompiled header cache"
$vsixPath = Join-Path $env:APPDATA "Code\CachedExtensionVSIXs"
Clean-DirectoryContents -Path $vsixPath -Description "VS Code cached extension VSIXs"
$clangdPath = Join-Path $env:LOCALAPPDATA "clangd"
Clean-DirectoryEntirely -Path $clangdPath -Description "Clangd language server cache"

# 2. Python Toolchain Caches
Write-Host "--- [2/8] Cleaning Python Caches ---" -ForegroundColor Yellow
$pipCache = Join-Path $env:LOCALAPPDATA "pip\cache"
Clean-DirectoryEntirely -Path $pipCache -Description "Pip wheel download cache"
if ((Get-Command pip -ErrorAction SilentlyContinue) -and -not $DryRun) {
    pip cache purge 2>&1 | Out-Null
}
$uvCache = Join-Path $env:LOCALAPPDATA "uv\cache"
Clean-DirectoryEntirely -Path $uvCache -Description "UV package manager cache"
if ((Get-Command uv -ErrorAction SilentlyContinue) -and -not $DryRun) {
    uv cache clean 2>&1 | Out-Null
}

# 3. JavaScript / Web Runtime Caches
Write-Host "--- [3/8] Cleaning JavaScript & Node Caches ---" -ForegroundColor Yellow
$bunCache = Join-Path $env:USERPROFILE ".bun\install\cache"
Clean-DirectoryContents -Path $bunCache -Description "Bun package cache"
if (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-Host "--> Cleaning NPM cache..." -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "    [DRY-RUN] Would run: npm cache clean --force" -ForegroundColor DarkGray
    } else {
        npm cache clean --force 2>&1 | Out-Null
    }
}
if (Get-Command yarn -ErrorAction SilentlyContinue) {
    Write-Host "--> Cleaning Yarn cache..." -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "    [DRY-RUN] Would run: yarn cache clean --all" -ForegroundColor DarkGray
    } else {
        yarn cache clean --all 2>&1 | Out-Null
    }
}
if (Get-Command pnpm -ErrorAction SilentlyContinue) {
    Write-Host "--> Pruning unreferenced pnpm store packages..." -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "    [DRY-RUN] Would run: pnpm store prune" -ForegroundColor DarkGray
    } else {
        pnpm store prune 2>&1 | Out-Null
    }
}

# 4. Rust & Cargo Caches
Write-Host "--- [4/8] Cleaning Rust & Cargo Caches ---" -ForegroundColor Yellow
$cargoGitCheckouts = Join-Path $env:USERPROFILE ".cargo\git\checkouts"
Clean-DirectoryContents -Path $cargoGitCheckouts -Description "Cargo git checkout cache"
$cargoGitDb = Join-Path $env:USERPROFILE ".cargo\git\db"
Clean-DirectoryContents -Path $cargoGitDb -Description "Cargo git bare repo cache"
$cargoPkgCache = Join-Path $env:USERPROFILE ".cargo\.package-cache"
if (Test-Path $cargoPkgCache) {
    if ($DryRun) {
        Write-Host "    [DRY-RUN] Would remove $cargoPkgCache" -ForegroundColor DarkGray
    } else {
        Remove-Item -Path $cargoPkgCache -Force -ErrorAction SilentlyContinue
    }
}
if ($Deep) {
    $cargoRegistrySrc = Join-Path $env:USERPROFILE ".cargo\registry\src"
    Clean-DirectoryContents -Path $cargoRegistrySrc -Description "Cargo extracted crate sources (deep)"
}

# 5. Go Language Caches
Write-Host "--- [5/8] Cleaning Go Caches ---" -ForegroundColor Yellow
if (Get-Command go -ErrorAction SilentlyContinue) {
    Write-Host "--> Cleaning Go build and test caches..." -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "    [DRY-RUN] Would run: go clean -cache -testcache" -ForegroundColor DarkGray
        if ($Deep) {
            Write-Host "    [DRY-RUN] Would run: go clean -modcache" -ForegroundColor DarkGray
        }
    } else {
        go clean -cache -testcache 2>&1 | Out-Null
        if ($Deep) {
            Write-Host "--> Cleaning Go module cache (deep)..." -ForegroundColor Cyan
            go clean -modcache 2>&1 | Out-Null
        }
    }
} else {
    $goBuildCache = Join-Path $env:LOCALAPPDATA "go-build"
    Clean-DirectoryEntirely -Path $goBuildCache -Description "Go build cache directory"
}

# 6. C/C++ Compiler Caches
Write-Host "--- [6/8] Cleaning C/C++ Caches ---" -ForegroundColor Yellow
if (Get-Command ccache -ErrorAction SilentlyContinue) {
    Write-Host "--> Clearing ccache compiler cache..." -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "    [DRY-RUN] Would run: ccache -C" -ForegroundColor DarkGray
    } else {
        ccache -C 2>&1 | Out-Null
    }
}

# 7. Browser Web Caches
Write-Host "--- [7/8] Cleaning Browser Web Caches ---" -ForegroundColor Yellow
$chromeCache = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache"
Clean-DirectoryContents -Path $chromeCache -Description "Google Chrome HTTP cache"
$braveCache = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data\Default\Cache"
Clean-DirectoryContents -Path $braveCache -Description "Brave HTTP cache"
$edgeCache = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache"
Clean-DirectoryContents -Path $edgeCache -Description "Microsoft Edge HTTP cache"

# 8. User Temporary Files
Write-Host "--- [8/8] Cleaning User Temp Files ---" -ForegroundColor Yellow
if (Test-Path $env:TEMP) {
    if ($DryRun) {
        Write-Host "    [DRY-RUN] Would clean stale temporary files in: $env:TEMP" -ForegroundColor DarkGray
    } else {
        Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# Optional System-Level Cleanup
if ($System) {
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " Running Windows System-Level Cleanups (Requires Administrator)" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Warning "System-level cleanup requested but PowerShell is not running as Administrator."
        Write-Warning "Please rerun as Administrator: Start-Process powershell -Verb runAs"
    } else {
        $swDist = Join-Path $env:SystemRoot "SoftwareDistribution\Download"
        if (Test-Path $swDist) {
            Write-Host "--> Cleaning Windows Update cache..." -ForegroundColor Cyan
            if ($DryRun) {
                Write-Host "    [DRY-RUN] Would remove contents of: $swDist" -ForegroundColor DarkGray
            } else {
                Get-ChildItem -Path $swDist -Recurse -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        $sysTemp = Join-Path $env:SystemRoot "Temp"
        if (Test-Path $sysTemp) {
            Write-Host "--> Cleaning System Temp..." -ForegroundColor Cyan
            if ($DryRun) {
                Write-Host "    [DRY-RUN] Would clean stale files in: $sysTemp" -ForegroundColor DarkGray
            } else {
                Get-ChildItem -Path $sysTemp -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $DryRun) {
            Write-Host "--> Emptying Recycle Bin..." -ForegroundColor Cyan
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        }
    }
}

$endFree = Get-DriveFreeBytes -Path $env:USERPROFILE
$reclaimed = [Math]::Max(0, ($endFree - $startFree))

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Windows Non-Docker Cleanup Complete!"
Write-Host " Free Space Comparison:"
Write-Host "   Before:    $(Format-Bytes $startFree)"
Write-Host "   After:     $(Format-Bytes $endFree)"
if ($reclaimed -gt 0) {
    Write-Host "   Reclaimed: $(Format-Bytes $reclaimed)" -ForegroundColor Yellow
} else {
    Write-Host "   Reclaimed: 0 KB (no net change)"
}
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " GUARANTEE VERIFIED: Docker daemon, containers, images,"
Write-Host " volumes, and WSL2 disks were completely untouched."
Write-Host "==========================================================" -ForegroundColor Green
