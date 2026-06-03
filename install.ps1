#requires -Version 5.1
<#
.SYNOPSIS
    Installs gpatcher to %LOCALAPPDATA%\gpatcher and adds it to the user PATH.
.DESCRIPTION
    Copies all required files (scripts, binaries, CMD wrapper) to a permanent
    install directory and ensures it is on the user's PATH so you can run
    'gpatcher' from any terminal.
.PARAMETER InstallDir
    Override the default install location. Defaults to %LOCALAPPDATA%\gpatcher.
.PARAMETER Uninstall
    Remove gpatcher from the install directory and clean it from PATH.
#>
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'gpatcher'),
    [switch]$Uninstall
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Add-ToUserPath {
    param([string]$Dir)
    $current = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = $current -split ';' | Where-Object { $_ -ne '' }
    if ($entries -contains $Dir) {
        Write-Host "  Already on PATH" -ForegroundColor Yellow
        return
    }
    $newPath = ($entries + $Dir) -join ';'
    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    # Also update current session
    $env:Path = "$env:Path;$Dir"
    Write-Host "  Added to user PATH" -ForegroundColor Green
}

function Remove-FromUserPath {
    param([string]$Dir)
    $current = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = $current -split ';' | Where-Object { $_ -ne '' -and $_ -ne $Dir }
    $newPath = $entries -join ';'
    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "  Removed from user PATH" -ForegroundColor Green
}

# --- Uninstall ---
if ($Uninstall) {
    Write-Host ""
    Write-Host "gpatcher uninstall" -ForegroundColor Cyan
    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
        Write-Host "  Removed: $InstallDir" -ForegroundColor Green
    } else {
        Write-Host "  Not found: $InstallDir" -ForegroundColor Yellow
    }
    Remove-FromUserPath $InstallDir
    Write-Host "  Done!" -ForegroundColor Green
    Write-Host ""
    exit 0
}

# --- Install ---
Write-Host ""
Write-Host "gpatcher installer" -ForegroundColor Cyan
Write-Host "  Source:  $PSScriptRoot" -ForegroundColor Gray
Write-Host "  Target:  $InstallDir" -ForegroundColor Gray
Write-Host ""

# Create install dir
if (Test-Path -LiteralPath $InstallDir) {
    Write-Host "  Removing old install..." -ForegroundColor Yellow
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Copy core files
$filesToCopy = @(
    'gpatcher.ps1',
    'gpatcher.cmd'
)
foreach ($f in $filesToCopy) {
    $src = Join-Path $PSScriptRoot $f
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $f) -Force
        Write-Host "  Copied: $f" -ForegroundColor Gray
    } else {
        Write-Host "  MISSING: $f" -ForegroundColor Red
        throw "Required file not found: $src"
    }
}

# Copy lib/
$libSrc = Join-Path $PSScriptRoot 'lib'
$libDst = Join-Path $InstallDir 'lib'
Copy-Item -LiteralPath $libSrc -Destination $libDst -Recurse -Force
Write-Host "  Copied: lib/ ($((Get-ChildItem $libDst -File).Count) files)" -ForegroundColor Gray

# Copy bin/
$binSrc = Join-Path $PSScriptRoot 'bin'
$binDst = Join-Path $InstallDir 'bin'
if (Test-Path -LiteralPath $binSrc) {
    Copy-Item -LiteralPath $binSrc -Destination $binDst -Recurse -Force
    Write-Host "  Copied: bin/ ($((Get-ChildItem $binDst -File).Count) files)" -ForegroundColor Gray
} else {
    Write-Host '  WARNING: bin/ not found -- run tools\fetch-hdiffpatch.ps1 after install' -ForegroundColor Yellow
}

# Add to PATH
Write-Host ""
Add-ToUserPath $InstallDir

Write-Host ""
Write-Host "  Installed! Restart your terminal, then run:" -ForegroundColor Green
Write-Host "    gpatcher doctor" -ForegroundColor White
Write-Host "    gpatcher help" -ForegroundColor White
Write-Host ""
