function Get-GameSlug {
    param([Parameter(Mandatory)][string]$Name)
    $s = $Name.ToLowerInvariant()
    $s = $s -replace '[^a-z0-9]+','-'
    $s = $s.Trim('-')
    if ($s.Length -gt 60) { $s = $s.Substring(0,60).TrimEnd('-') }
    if (-not $s) { throw "Game name produces empty slug: $Name" }
    $s
}

function New-Manifest {
    param(
        [Parameter(Mandatory)][string]$Game,
        [Parameter(Mandatory)][string]$OldVersion,
        [Parameter(Mandatory)][string]$NewVersion,
        [Parameter(Mandatory)][string]$OldRootHash,
        [Parameter(Mandatory)][string]$NewRootHash,
        [Parameter(Mandatory)][object[]]$Ops
    )
    [pscustomobject]@{
        schema          = 1
        tool            = 'gpatcher 0.1'
        game            = $Game
        game_slug       = (Get-GameSlug $Game)
        old_version     = $OldVersion
        new_version     = $NewVersion
        created_utc     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        old_root_sha256 = $OldRootHash
        new_root_sha256 = $NewRootHash
        ops             = $Ops
    }
}

function Write-ManifestFile {
    param(
        [Parameter(Mandatory)][object]$Manifest,
        [Parameter(Mandatory)][string]$Path
    )
    $json = $Manifest | ConvertTo-Json -Depth 32
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Read-ManifestFile {
    param([Parameter(Mandatory)][string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    $m = $text | ConvertFrom-Json
    if ($m.schema -ne 1) {
        throw "Unsupported manifest schema: $($m.schema) (expected 1)"
    }
    $m
}
