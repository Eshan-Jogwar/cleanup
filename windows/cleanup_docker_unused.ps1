<#
==============================================================================
Windows Developer Disk Cleanup - Purge All Unused Docker Resources Script
Removes EVERYTHING in Docker not currently in active use on Windows:
  - Stopped / exited containers
  - Images not used by any running container (both dangling & unused tagged)
  - Local volumes not attached to any container
  - Unused custom networks
  - BuildKit build cache

GUARANTEE: Running containers, images in use, and attached volumes stay intact.
Host non-Docker files are never touched.
==============================================================================
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Help
)

$ErrorActionPreference = 'SilentlyContinue'

if ($Help) {
    Write-Host @"
Usage: .\windows\cleanup_docker_unused.ps1 [OPTIONS]

Remove all Docker containers, images, volumes, and build caches not currently in use on Windows.

OPTIONS:
  -DryRun      Display inactive Docker items and reclaimable space without deleting.
  -Force       Skip confirmation prompt and purge immediately.
  -Help        Show this help message.

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
  - All host Windows filesystem files outside Docker
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
    $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
    return $drive.Free
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Error: 'docker' CLI not found on PATH."
    exit 1
}

docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Cannot connect to Docker daemon. Ensure Docker Desktop for Windows is running."
    exit 1
}

$startFree = Get-DriveFreeBytes

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Windows Docker Purge: All Unused Resources"
if ($DryRun) {
    Write-Host " MODE: DRY RUN (inspection only, no modifications)"
} else {
    Write-Host " MODE: PURGE ALL UNUSED DOCKER DATA"
}
Write-Host " Guaranteed: Running containers & attached volumes stay intact."
Write-Host "==========================================================" -ForegroundColor Green

Write-Host "--> Initial System Free Space ($($env:SystemDrive)): $(Format-Bytes $startFree)"
Write-Host ""
Write-Host "--> Current Docker Resource Breakdown:"
docker system df
Write-Host "==========================================================" -ForegroundColor Green

$stoppedContainers = (docker ps -a --filter "status=exited" --filter "status=created" -q | Measure-Object).Count
$runningContainers = (docker ps --filter "status=running" -q | Measure-Object).Count

Write-Host "Container Status: $runningContainers running (safe), $stoppedContainers stopped/dormant (to remove)."

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY-RUN] The following commands would be executed:"
    Write-Host "  1. docker container prune -f        (Remove $stoppedContainers stopped containers)"
    Write-Host "  2. docker network prune -f          (Remove unused custom networks)"
    Write-Host "  3. docker image prune -a -f         (Remove ALL images not used by running containers)"
    Write-Host "  4. docker volume prune -a -f        (Remove ALL volumes not attached to any container)"
    Write-Host "  5. docker builder prune -a -f       (Remove complete BuildKit build cache)"
    Write-Host ""
    Write-Host "[DRY-RUN] To purge these resources, run without -DryRun."
    exit 0
}

if (-not $Force) {
    Write-Host ""
    Write-Host "WARNING: This will permanently delete:" -ForegroundColor Yellow
    Write-Host "  - All stopped containers ($stoppedContainers containers)"
    Write-Host "  - All images not currently used by running containers"
    Write-Host "  - All volumes not currently attached to any container"
    Write-Host "  - All BuildKit build cache"
    Write-Host ""
    $confirm = Read-Host "Are you sure you want to purge all unused Docker resources? [y/N]"
    if ($confirm -notmatch '^[yY]([eE][sS])?$') {
        Write-Host "Operation cancelled by user. Nothing removed."
        exit 0
    }
}

Write-Host ""
Write-Host "--> 1/5 Removing stopped containers..." -ForegroundColor Cyan
docker container prune -f

Write-Host "--> 2/5 Removing unused custom networks..." -ForegroundColor Cyan
docker network prune -f

Write-Host "--> 3/5 Removing ALL unused images..." -ForegroundColor Cyan
docker image prune -a -f

Write-Host "--> 4/5 Removing ALL unattached volumes..." -ForegroundColor Cyan
docker volume prune -a -f 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    docker volume prune -f 2>&1 | Out-Null
}

Write-Host "--> 5/5 Removing complete BuildKit builder cache..." -ForegroundColor Cyan
docker builder prune -a -f 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    docker buildx prune -a -f 2>&1 | Out-Null
}

docker system prune -a --volumes -f 2>&1 | Out-Null

$endFree = Get-DriveFreeBytes
$reclaimed = [Math]::Max(0, ($endFree - $startFree))

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Windows Docker Purge Complete!"
Write-Host " Updated Docker Disk Breakdown:"
docker system df
Write-Host ""
Write-Host " Free Space Comparison ($($env:SystemDrive)):"
Write-Host "   Before:    $(Format-Bytes $startFree)"
Write-Host "   After:     $(Format-Bytes $endFree)"
if ($reclaimed -gt 0) {
    Write-Host "   Reclaimed: $(Format-Bytes $reclaimed)" -ForegroundColor Yellow
} else {
    Write-Host "   Reclaimed: 0 KB (no net change)"
}
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Running containers, their images, and attached volumes"
Write-Host " remain active and untouched."
Write-Host "==========================================================" -ForegroundColor Green
