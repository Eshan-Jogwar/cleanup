<#
==============================================================================
Windows Developer Disk Cleanup - System Space Script (Requires Administrator)
Safely reclaims Windows Update cache, System Temp, WER crash reports, and package caches.
==============================================================================
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

function Test-IsAdministrator {
    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Error "Please run this script as Administrator (Right click PowerShell -> Run as Administrator)."
    exit 1
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
    $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
    return $drive.Free
}

$startFree = Get-DriveFreeBytes

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Starting Windows System-Level Disk Cleanup (Administrator)"
Write-Host " Initial Free Space ($($env:SystemDrive)): $(Format-Bytes $startFree)"
Write-Host "==========================================================" -ForegroundColor Green

# 1. Windows Update Download Cache (SoftwareDistribution\Download)
$swDistDownload = Join-Path $env:SystemRoot "SoftwareDistribution\Download"
if (Test-Path $swDistDownload) {
    Write-Host "--> Cleaning Windows Update downloaded files..." -ForegroundColor Cyan
    Get-ChildItem -Path $swDistDownload -Recurse -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 2. System-wide Temp Files (C:\Windows\Temp)
$systemTemp = Join-Path $env:SystemRoot "Temp"
if (Test-Path $systemTemp) {
    Write-Host "--> Cleaning System Temp in $systemTemp..." -ForegroundColor Cyan
    Get-ChildItem -Path $systemTemp -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# 3. Windows Error Reporting (WER) Crash Archives
$werArchive = Join-Path $env:ProgramData "Microsoft\Windows\WER\ReportArchive"
$werQueue = Join-Path $env:ProgramData "Microsoft\Windows\WER\ReportQueue"
if (Test-Path $werArchive) {
    Write-Host "--> Cleaning WER crash reports..." -ForegroundColor Cyan
    Get-ChildItem -Path $werArchive -Recurse -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
if (Test-Path $werQueue) {
    Get-ChildItem -Path $werQueue -Recurse -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 4. Package Manager Caches (winget / choco / scoop)
if (Get-Command winget -ErrorAction SilentlyContinue) {
    $wingetCache = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState"
    if (Test-Path $wingetCache) {
        Write-Host "--> Cleaning WinGet cache..." -ForegroundColor Cyan
        Get-ChildItem -Path $wingetCache -Filter "*.msixbundle" -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Host "--> Cleaning Chocolatey cache..." -ForegroundColor Cyan
    choco cache clean 2>&1 | Out-Null
}
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "--> Cleaning Scoop cache..." -ForegroundColor Cyan
    scoop cache rm * 2>&1 | Out-Null
}

# 5. Flush DNS Cache
Write-Host "--> Flushing DNS resolver cache..." -ForegroundColor Cyan
ipconfig /flushdns 2>&1 | Out-Null

# 6. Empty Recycle Bin
Write-Host "--> Emptying Recycle Bin..." -ForegroundColor Cyan
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

$endFree = Get-DriveFreeBytes
$reclaimed = [Math]::Max(0, ($endFree - $startFree))

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Windows System-Level Cleanup Complete!"
Write-Host " Free Space Comparison ($($env:SystemDrive)):"
Write-Host "   Before:    $(Format-Bytes $startFree)"
Write-Host "   After:     $(Format-Bytes $endFree)"
if ($reclaimed -gt 0) {
    Write-Host "   Reclaimed: $(Format-Bytes $reclaimed)" -ForegroundColor Yellow
} else {
    Write-Host "   Reclaimed: 0 KB (no net change)"
}
Write-Host "==========================================================" -ForegroundColor Green
