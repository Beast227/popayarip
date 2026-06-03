Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function LogInfo($msg) { Write-Host "[info]  $msg" -ForegroundColor Cyan }
function LogWarn($msg) { Write-Host "[warn]  $msg" -ForegroundColor Yellow }
function LogErr($msg)  { Write-Host "[err]   $msg" -ForegroundColor Red }
function LogOk($msg)   { Write-Host "[ok]    $msg" -ForegroundColor Green }

function Get-ToolRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-BinPath {
    param([Parameter(Mandatory)][string]$Name)
    Join-Path (Join-Path (Get-ToolRoot) 'bin') $Name
}

function Get-RelPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Full
    )
    $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\','/')
    $f = (Resolve-Path -LiteralPath $Full).Path
    if (-not $f.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path $Full not under $Root"
    }
    $rel = $f.Substring($rootFull.Length).TrimStart('\','/')
    $rel -replace '\\','/'
}

function ConvertTo-NativePath {
    param([Parameter(Mandatory)][string]$RelPath)
    $RelPath -replace '/','\'
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function New-TempDir {
    param([string]$Prefix = 'gpatcher')
    $base = [System.IO.Path]::GetTempPath()
    $name = "$Prefix-$([guid]::NewGuid().ToString('N').Substring(0,12))"
    $p = Join-Path $base $name
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    $p
}

function Remove-PathSafe {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Format-Bytes {
    param([Parameter(Mandatory)][long]$Bytes)
    $units = 'B','KB','MB','GB','TB'
    $i = 0
    $v = [double]$Bytes
    while ($v -ge 1024 -and $i -lt ($units.Length - 1)) {
        $v = $v / 1024
        $i++
    }
    '{0:N2} {1}' -f $v, $units[$i]
}

function Assert-NotReparse {
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)
    if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "Symlink/junction not supported: $($Item.FullName)"
    }
}
