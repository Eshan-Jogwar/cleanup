<#
==============================================================================
Windows Developer Disk Cleanup - User Space Script (No Admin Required)
Safely reclaims user-space package manager caches, IDE caches, and browser caches.
==============================================================================
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

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

function Clean-DirectoryContents {
    param(
        [string]$Path,
        [string]$Description
    )
    if (Test-Path -Path $Path) {
        Write-Host "--> $Description ($Path)..." -ForegroundColor Cyan
        Get-ChildItem -Path $Path -Force -Recurse -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Clean-DirectoryEntirely {
    param(
        [string]$Path,
        [string]$Description
    )
    if (Test-Path -Path $Path) {
        Write-Host "--> $Description ($Path)..." -ForegroundColor Cyan
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$startFree = Get-DriveFreeBytes -Path $env:USERPROFILE

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Starting Windows User-Level Disk Cleanup"
Write-Host " Initial Free Space: $(Format-Bytes $startFree)"
Write-Host "==========================================================" -ForegroundColor Green

# 1. VS Code C/C++ Extension Precompiled Headers
$ipchPath = Join-Path $env:LOCALAPPDATA "Microsoft\vscode-cpptools\ipch"
Clean-DirectoryContents -Path $ipchPath -Description "VS Code C++ precompiled header cache"

# 2. VS Code Cached Extension Installers
$vsixPath = Join-Path $env:APPDATA "Code\CachedExtensionVSIXs"
Clean-DirectoryContents -Path $vsixPath -Description "VS Code cached extension VSIXs"

# 3. Pip HTTP Download Cache
$pipCache = Join-Path $env:LOCALAPPDATA "pip\cache"
Clean-DirectoryEntirely -Path $pipCache -Description "Pip wheel download cache"
if (Get-Command pip -ErrorAction SilentlyContinue) {
    pip cache purge 2>&1 | Out-Null
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    python -m pip cache purge 2>&1 | Out-Null
}

# 4. UV Cache
$uvCache = Join-Path $env:LOCALAPPDATA "uv\cache"
Clean-DirectoryEntirely -Path $uvCache -Description "UV package manager cache"
if (Get-Command uv -ErrorAction SilentlyContinue) {
    uv cache clean 2>&1 | Out-Null
}

# 5. Bun Package Cache
$bunCache = Join-Path $env:USERPROFILE ".bun\install\cache"
Clean-DirectoryContents -Path $bunCache -Description "Bun package cache"

# 6. NPM Cache
if (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-Host "--> Cleaning NPM cache..." -ForegroundColor Cyan
    npm cache clean --force 2>&1 | Out-Null
}

# 7. Go Build & Module Cache
if (Get-Command go -ErrorAction SilentlyContinue) {
    Write-Host "--> Cleaning Go build cache..." -ForegroundColor Cyan
    go clean -cache 2>&1 | Out-Null
}

# 8. Browser Web Caches
$chromeCache = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache"
Clean-DirectoryContents -Path $chromeCache -Description "Google Chrome HTTP cache"

$braveCache = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data\Default\Cache"
Clean-DirectoryContents -Path $braveCache -Description "Brave HTTP cache"

$edgeCache = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache"
Clean-DirectoryContents -Path $edgeCache -Description "Microsoft Edge HTTP cache"

# 9. User Temporary Files (safe cleanup of files older than 3 days)
if (Test-Path $env:TEMP) {
    Write-Host "--> Cleaning user temporary files in $env:TEMP..." -ForegroundColor Cyan
    Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

$endFree = Get-DriveFreeBytes -Path $env:USERPROFILE
$reclaimed = [Math]::Max(0, ($endFree - $startFree))

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Windows User-Level Cleanup Complete!"
Write-Host " Free Space Comparison:"
Write-Host "   Before:    $(Format-Bytes $startFree)"
Write-Host "   After:     $(Format-Bytes $endFree)"
if ($reclaimed -gt 0) {
    Write-Host "   Reclaimed: $(Format-Bytes $reclaimed)" -ForegroundColor Yellow
} else {
    Write-Host "   Reclaimed: 0 KB (no net change)"
}
Write-Host "==========================================================" -ForegroundColor Green
