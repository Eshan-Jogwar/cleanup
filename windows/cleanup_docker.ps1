<#
==============================================================================
Windows Developer Disk Cleanup - Dedicated Docker Cleanup Script
ONLY touches Docker resources (containers, images, build cache, networks, volumes).
Host programmer files, Windows caches, and non-Docker data are NOT touched.
==============================================================================
#>
[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Volumes,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = 'SilentlyContinue'

if ($Help) {
    Write-Host @"
Usage: .\windows\cleanup_docker.ps1 [OPTIONS]

Reclaim disk space occupied exclusively by Docker on Windows.

OPTIONS:
  -All         Prune ALL unused images (not just dangling ones)
               and all builder cache.
  -Volumes     Prune unused Docker volumes (WARNING: removes unmounted
               data volumes; use only if you don't need orphan volume data).
  -DryRun      Display current Docker disk breakdown without deleting anything.
  -Help        Show this help message.

DEFAULT BEHAVIOR (Safe Prune):
  - Prunes stopped containers
  - Prunes dangling images (<none>:<none>)
  - Prunes dangling / untagged build cache
  - Prunes unused Docker networks
  - Leaves running containers, tagged images, and volumes intact.
  - ZERO changes to any files outside Docker.
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
    Write-Error "Error: 'docker' CLI is not installed or not in PATH."
    exit 1
}

docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Cannot connect to the Docker daemon. Ensure Docker Desktop for Windows is running."
    exit 1
}

$startFree = Get-DriveFreeBytes

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Windows Docker-Only Disk Cleanup (DOCKER ONLY)"
Write-Host " Guaranteed: Non-Docker files and Windows caches are untouched."
if ($DryRun) {
    Write-Host " MODE: DRY RUN (no modifications will be made)"
} elseif ($All) {
    Write-Host " MODE: DEEP PRUNE (pruning all unused images & all build cache)"
} else {
    Write-Host " MODE: SAFE PRUNE (dangling images & build cache only)"
}
if ($Volumes) {
    Write-Host " VOLUMES: Unused volumes WILL be pruned"
}
Write-Host "==========================================================" -ForegroundColor Green

Write-Host "--> Initial System Free Space ($($env:SystemDrive)): $(Format-Bytes $startFree)"
Write-Host ""
Write-Host "--> Initial Docker Disk Breakdown:"
docker system df
Write-Host "==========================================================" -ForegroundColor Green

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY-RUN] The following actions would be performed:"
    Write-Host "  1. docker container prune -f (Remove stopped containers)"
    Write-Host "  2. docker network prune -f (Remove unused custom networks)"
    if ($All) {
        Write-Host "  3. docker image prune -a -f (Remove ALL unused images)"
        Write-Host "  4. docker builder prune -a -f (Remove ALL build cache)"
    } else {
        Write-Host "  3. docker image prune -f (Remove dangling images only)"
        Write-Host "  4. docker builder prune -f (Remove dangling build cache only)"
    }
    if ($Volumes) {
        Write-Host "  5. docker volume prune -f (Remove unused local volumes)"
    }
    Write-Host ""
    Write-Host "[DRY-RUN] To execute, run without -DryRun."
    exit 0
}

# 1. Stopped Containers
Write-Host "--> 1/5 Pruning stopped containers..." -ForegroundColor Cyan
docker container prune -f

# 2. Unused Networks
Write-Host "--> 2/5 Pruning unused networks..." -ForegroundColor Cyan
docker network prune -f

# 3. Images
if ($All) {
    Write-Host "--> 3/5 Pruning ALL unused Docker images..." -ForegroundColor Cyan
    docker image prune -a -f
} else {
    Write-Host "--> 3/5 Pruning dangling Docker images (<none>:<none>)..." -ForegroundColor Cyan
    docker image prune -f
}

# 4. Build Cache
if ($All) {
    Write-Host "--> 4/5 Pruning ALL build cache..." -ForegroundColor Cyan
    docker builder prune -a -f 2>&1 | Out-Null
} else {
    Write-Host "--> 4/5 Pruning dangling/expired build cache..." -ForegroundColor Cyan
    docker builder prune -f 2>&1 | Out-Null
}

# 5. Volumes
if ($Volumes) {
    Write-Host "--> 5/5 Pruning unused volumes..." -ForegroundColor Cyan
    docker volume prune -f
} else {
    Write-Host "--> 5/5 Skipping volumes (use -Volumes to prune unused volumes)." -ForegroundColor DarkGray
}

# 6. Docker Desktop rotated logs
$dockerLogPaths = @(
    (Join-Path $env:LOCALAPPDATA "Docker\log"),
    (Join-Path $env:APPDATA "Docker\log")
)
foreach ($dlp in $dockerLogPaths) {
    if (Test-Path $dlp) {
        Write-Host "--> Cleaning rotated Docker Desktop logs in $dlp..." -ForegroundColor Cyan
        Get-ChildItem -Path $dlp -Filter "*.log.*" -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

$endFree = Get-DriveFreeBytes
$reclaimed = [Math]::Max(0, ($endFree - $startFree))

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Windows Docker Cleanup Complete!"
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
Write-Host " Guaranteed: Only Docker was cleaned. Host files, IDE caches,"
Write-Host " and code repositories were completely untouched."
Write-Host "==========================================================" -ForegroundColor Green
