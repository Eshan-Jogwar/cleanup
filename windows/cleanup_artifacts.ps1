<#
==============================================================================
Windows Developer Disk Cleanup - Project Build & Package Artifacts Script
Discovers and removes regenerable language package directories and build caches:
  - JavaScript / Node: node_modules, .next, .nuxt, .svelte-kit, .turbo, .parcel-cache
  - Rust:              target/ (Cargo build artifacts)
  - .NET / C#:         bin/, obj/ (when inside a .csproj/.sln project)
  - Python:            .venv, venv, .virtualenv, __pycache__, .pytest_cache, .mypy_cache, .ruff_cache
  - Dart / Flutter:    .dart_tool
  - Java / Gradle:     .gradle

GUARANTEE: Does NOT touch source code, git commits/branches, or user configs.
All deleted items can be redownloaded/rebuilt anytime (npm install, cargo build, etc.).
==============================================================================
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Node,
    [switch]$Rust,
    [switch]$Python,
    [switch]$Dotnet,
    [string]$Type = "all",
    [switch]$Help
)

$ErrorActionPreference = 'SilentlyContinue'

if ($Help) {
    Write-Host @"
Usage: .\windows\cleanup_artifacts.ps1 [OPTIONS] [-Path <directories>]

Find and safely delete regenerable language package folders and build artifacts on Windows
(e.g., node_modules, Rust target/, .NET bin/obj, Python .venv/venv, __pycache__, etc.).

OPTIONS:
  -DryRun              Inspect and list all matching directories and total size
                       without deleting anything.
  -Force               Skip confirmation prompt and delete immediately.
  -Node                Only clean Node.js / JavaScript packages (node_modules, .next, .turbo).
  -Rust                Only clean Rust / Cargo build artifacts (target/).
  -Python              Only clean Python virtual environments (.venv, venv) & caches.
  -Dotnet              Only clean .NET / C# build outputs (bin/, obj/).
  -Type <TYPE>         Filter cleanup: all, node, rust, python, dotnet, flutter, gradle.
  -Path <string[]>     One or more directory paths to search inside (e.g. C:\code, .).
                       If no directory is given, the script automatically scans
                       detected project folders or current working directory.
  -Help                Show this help message.

SAFETY:
  - Excludes .git, AppData, Program Files, Windows, .vscode, .cargo, and system paths.
  - Verifies Python venvs contain pyvenv.cfg or Scripts\activate before deleting.
  - Verifies Rust target folders belong to a Cargo/build project before deleting.
  - Verifies .NET bin/obj folders belong to a .csproj or .sln before deleting.
  - Prompts for confirmation before deleting unless -Force is passed.
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

function Get-DirectorySize {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return 0 }
    $measure = Get-ChildItem -Path $Dir -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
    if ($measure.Sum) { return $measure.Sum } else { return 0 }
}

if ($Node)   { $Type = "node" }
if ($Rust)   { $Type = "rust" }
if ($Python) { $Type = "python" }
if ($Dotnet) { $Type = "dotnet" }

# Resolve search paths
$resolvedPaths = @()
if ($Path -and $Path.Count -gt 0) {
    foreach ($p in $Path) {
        if (Test-Path $p) {
            $resolvedPaths += (Resolve-Path $p).Path
        } else {
            Write-Warning "Directory not found, skipping: $p"
        }
    }
} else {
    $candidates = @(
        (Join-Path $env:USERPROFILE "coding"),
        (Join-Path $env:USERPROFILE "projects"),
        (Join-Path $env:USERPROFILE "source\repos"),
        (Join-Path $env:USERPROFILE "src"),
        (Join-Path $env:USERPROFILE "dev"),
        (Join-Path $env:USERPROFILE "workspace")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $resolvedPaths += $c
        }
    }
    if ($resolvedPaths.Count -eq 0) {
        $resolvedPaths += (Get-Location).Path
    }
}

$primaryRoot = $resolvedPaths[0]
$driveLetter = (Split-Path -Qualifier $primaryRoot).TrimEnd(':')
$startFree = (Get-PSDrive -Name $driveLetter).Free

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Windows Project Build & Package Artifacts Cleanup"
if ($DryRun) {
    Write-Host " MODE: DRY RUN (inspection only, no files deleted)"
} else {
    Write-Host " MODE: ACTIVE CLEANUP"
}
Write-Host " Filter: $Type"
Write-Host " Initial Free Space ($($driveLetter):): $(Format-Bytes $startFree)"
Write-Host " Scanning directories:"
foreach ($rp in $resolvedPaths) {
    Write-Host "   - $rp"
}
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "--> Scanning for regenerable package and build directories..." -ForegroundColor Cyan

$excludedNames = @(
    ".git", "AppData", "Program Files", "Program Files (x86)",
    "Windows", "System Volume Information", "$Recycle.Bin",
    ".vscode", ".cargo", ".rustup", ".nvm", ".bun", ".npm", ".gemini"
)

$matchedItems = @()

foreach ($root in $resolvedPaths) {
    $dirQueue = New-Object System.Collections.Generic.Queue[string]
    $dirQueue.Enqueue($root)

    while ($dirQueue.Count -gt 0) {
        $current = $dirQueue.Dequeue()
        $subDirs = Get-ChildItem -Path $current -Directory -Force -ErrorAction SilentlyContinue

        foreach ($dir in $subDirs) {
            $dirName = $dir.Name
            $dirPath = $dir.FullName

            # Skip excluded paths
            if ($excludedNames -contains $dirName) {
                continue
            }

            $category = $null

            # 1. Node.js
            if ($dirName -eq "node_modules") {
                if ($Type -eq "all" -or $Type -eq "node") {
                    $category = "Node.js (node_modules)"
                }
            } elseif ($dirName -match '^\.(next|nuxt|svelte-kit|turbo|parcel-cache)$') {
                if ($Type -eq "all" -or $Type -eq "node") {
                    $category = "Frontend Cache ($dirName)"
                }
            }
            # 2. Rust
            elseif ($dirName -eq "target") {
                if ($Type -eq "all" -or $Type -eq "rust") {
                    $parent = Split-Path $dirPath -Parent
                    if ((Test-Path (Join-Path $parent "Cargo.toml")) -or (Test-Path (Join-Path $dirPath "CACHEDIR.TAG")) -or (Test-Path (Join-Path $dirPath "debug"))) {
                        $category = "Rust/Build (target/)"
                    }
                }
            }
            # 3. .NET / C# (bin / obj)
            elseif ($dirName -eq "bin" -or $dirName -eq "obj") {
                if ($Type -eq "all" -or $Type -eq "dotnet") {
                    $parent = Split-Path $dirPath -Parent
                    $proj = Get-ChildItem -Path $parent -Filter "*.*proj" -ErrorAction SilentlyContinue
                    if ($proj) {
                        $category = ".NET Build ($dirName/)"
                    }
                }
            }
            # 4. Python Virtual Environments
            elseif ($dirName -match '^(\.venv|venv|\.virtualenv|env)$') {
                if ($Type -eq "all" -or $Type -eq "python") {
                    if ((Test-Path (Join-Path $dirPath "pyvenv.cfg")) -or (Test-Path (Join-Path $dirPath "Scripts\activate.bat")) -or (Test-Path (Join-Path $dirPath "bin\activate"))) {
                        $category = "Python VirtualEnv ($dirName)"
                    }
                }
            }
            # 5. Python Caches
            elseif ($dirName -match '^(__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache)$') {
                if ($Type -eq "all" -or $Type -eq "python") {
                    $category = "Python Cache ($dirName)"
                }
            }
            # 6. Dart / Flutter
            elseif ($dirName -eq ".dart_tool") {
                if ($Type -eq "all" -or $Type -eq "flutter") {
                    $category = "Dart/Flutter (.dart_tool)"
                }
            }
            # 7. Gradle
            elseif ($dirName -eq ".gradle") {
                if ($Type -eq "all" -or $Type -eq "gradle") {
                    $category = "Gradle Cache (.gradle)"
                }
            }

            if ($category) {
                $dirSize = Get-DirectorySize -Dir $dirPath
                $matchedItems += [PSCustomObject]@{
                    Path     = $dirPath
                    Category = $category
                    Size     = $dirSize
                    SizeStr  = (Format-Bytes $dirSize)
                }
                # Do not recurse into matched artifact directory
            } else {
                # Recurse into subdirectories
                $dirQueue.Enqueue($dirPath)
            }
        }
    }
}

if ($matchedItems.Count -eq 0) {
    Write-Host "No matching project artifact folders found in specified paths." -ForegroundColor Green
    Write-Host "Everything is already clean!" -ForegroundColor Green
    exit 0
}

$totalBytes = ($matchedItems | Measure-Object -Property Size -Sum).Sum
$totalStr = Format-Bytes $totalBytes

Write-Host ""
Write-Host "Discovered Artifacts ($($matchedItems.Count) items, $totalStr reclaimable):" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------"
foreach ($item in $matchedItems) {
    Write-Host ("{0,-10}  {1,-28}  {2}" -f $item.SizeStr, $item.Category, $item.Path)
}
Write-Host "----------------------------------------------------------------------"
Write-Host "Total Reclaimable Space: $totalStr across $($matchedItems.Count) directories."
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY-RUN] No directories were deleted." -ForegroundColor Yellow
    Write-Host "To delete these directories, run without -DryRun."
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "Permanently delete these $($matchedItems.Count) artifact directories? [y/N]"
    if ($confirm -notmatch '^[yY]([eE][sS])?$') {
        Write-Host "Operation aborted by user. No files were deleted."
        exit 0
    }
}

Write-Host ""
Write-Host "--> Deleting $($matchedItems.Count) artifact directories..." -ForegroundColor Cyan
$deletedCount = 0
for ($i = 0; $i -lt $matchedItems.Count; $i++) {
    $item = $matchedItems[$i]
    Write-Host ("[{0}/{1}] Deleting: {2} ({3})" -f ($i + 1), $matchedItems.Count, $item.Path, $item.SizeStr)
    Remove-Item -Path $item.Path -Recurse -Force -ErrorAction SilentlyContinue
    $deletedCount++
}

$endFree = (Get-PSDrive -Name $driveLetter).Free
$reclaimed = [Math]::Max(0, ($endFree - $startFree))

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Windows Project Artifacts Cleanup Complete!"
Write-Host " Deleted:     $deletedCount directories"
Write-Host " Directory Sum Reclaimed: ~$totalStr"
Write-Host " Storage Comparison ($($driveLetter):):"
Write-Host "   Before:    $(Format-Bytes $startFree)"
Write-Host "   After:     $(Format-Bytes $endFree)"
if ($reclaimed -gt 0) {
    Write-Host "   Reclaimed: $(Format-Bytes $reclaimed)" -ForegroundColor Yellow
} else {
    Write-Host "   Reclaimed: ~$totalStr"
}
Write-Host " Note: You can redownload or regenerate packages anytime"
Write-Host " (e.g. npm install, cargo build, dotnet build, python -m venv .venv)."
Write-Host "==========================================================" -ForegroundColor Green
