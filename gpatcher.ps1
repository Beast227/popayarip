#requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\Hash.ps1')
. (Join-Path $PSScriptRoot 'lib\Walk.ps1')
. (Join-Path $PSScriptRoot 'lib\Manifest.ps1')
. (Join-Path $PSScriptRoot 'lib\Diff.ps1')
. (Join-Path $PSScriptRoot 'lib\Archive.ps1')
. (Join-Path $PSScriptRoot 'lib\Create.ps1')
. (Join-Path $PSScriptRoot 'lib\Apply.ps1')
. (Join-Path $PSScriptRoot 'lib\Restore.ps1')
. (Join-Path $PSScriptRoot 'lib\IA.ps1')
. (Join-Path $PSScriptRoot 'lib\Update.ps1')
. (Join-Path $PSScriptRoot 'lib\Interactive.ps1')

function Show-Usage {
@'
gpatcher -- game patch producer/consumer

Usage:
  gpatcher create  --old <dir> --new <dir> --game <name> --old-ver <v> --new-ver <v> [--out <dir>]
  gpatcher apply   --patch <path-or-url> --target <install-dir> [--dry-run] [--no-backup] [--keep-backup]
  gpatcher restore --target <install-dir> [--backup <dir-or-latest>] [--keep-backup]
  gpatcher upload  --patch <bundle.zip> [--creator <name>] [--description <text>]
  gpatcher search  <game-name>
  gpatcher fetch   --game <slug> --from <v> --to <v> [--out <dir>]
  gpatcher verify  --install <dir> --against <manifest-or-bundle>
  gpatcher doctor
  gpatcher ui      -- start interactive console UI
  gpatcher webui   -- start web UI dashboard
  gpatcher update  [--force]
  gpatcher uninstall
  gpatcher help
'@
}

function Read-Flags {
    param([string[]]$ArgList = @())
    if ($null -eq $ArgList) { $ArgList = @() }
    $flags = @{}
    $positional = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $ArgList.Count) {
        $a = $ArgList[$i]
        if ($a -like '--*') {
            $key  = $a.Substring(2)
            $next = if (($i + 1) -lt $ArgList.Count) { $ArgList[$i + 1] } else { $null }
            if ($null -ne $next -and -not ($next -like '--*')) {
                $flags[$key] = $next
                $i += 2
            } else {
                $flags[$key] = $true
                $i++
            }
        } else {
            $positional.Add($a)
            $i++
        }
    }
    @{ Flags = $flags; Positional = $positional.ToArray() }
}

function Get-RequiredFlag {
    param([hashtable]$Flags, [string]$Name)
    if (-not $Flags.ContainsKey($Name)) { throw "Missing required flag: --$Name" }
    $Flags[$Name]
}

function Get-OptionalFlag {
    param([hashtable]$Flags, [string]$Name, $Default)
    if ($Flags.ContainsKey($Name)) { $Flags[$Name] } else { $Default }
}

function Invoke-Doctor {
    LogInfo "gpatcher doctor"
    $hdiffz  = Get-BinPath 'hdiffz.exe'
    $hpatchz = Get-BinPath 'hpatchz.exe'
    foreach ($e in @($hdiffz, $hpatchz)) {
        $leaf = Split-Path $e -Leaf
        if (Test-Path -LiteralPath $e) {
            $sz = (Get-Item -LiteralPath $e).Length
            LogOk "  ${leaf}: $(Format-Bytes $sz)"
        } else {
            LogErr "  ${leaf}: MISSING -- run tools\fetch-hdiffpatch.ps1"
        }
    }
    if (Test-CommandExists 'python') {
        $v = (& python --version) 2>&1
        LogOk "  python: $v"
    } else {
        LogWarn "  python: not found (needed for upload/search/fetch)"
    }
    if (Test-CommandExists 'ia') {
        $v = (& ia --version) 2>&1
        LogOk "  ia: $v"
    } else {
        LogWarn "  ia: not found -- pip install internetarchive"
    }
}

function Invoke-Verify {
    param([string]$Install, [string]$Against)
    if (-not (Test-Path -LiteralPath $Install -PathType Container)) {
        throw "Install dir not found: $Install"
    }
    if (-not (Test-Path -LiteralPath $Against)) {
        throw "Manifest/bundle not found: $Against"
    }
    $staging = $null
    try {
        $manifestPath = $null
        if ($Against -like '*.zip') {
            $staging = New-TempDir 'gpatcher-verify'
            Expand-Dir -ZipPath $Against -DestDir $staging
            $manifestPath = Join-Path $staging 'manifest.json'
        } else {
            $manifestPath = $Against
        }
        $m = Read-ManifestFile -Path $manifestPath
        LogInfo "Verifying $Install against $($m.game) $($m.old_version) snapshot"
        $bad = 0
        foreach ($op in $m.ops) {
            $expected = $null
            switch ($op.op) {
                'keep'   { $expected = $op.sha256 }
                'diff'   { $expected = $op.old_sha256 }
                'delete' { $expected = $op.old_sha256 }
                'add'    { $expected = $null }
            }
            if ($null -eq $expected) { continue }
            $p = Join-Path $Install (ConvertTo-NativePath $op.path)
            if (-not (Test-Path -LiteralPath $p)) {
                LogErr "  missing: $($op.path)"
                $bad++
                continue
            }
            if ((Get-FileSha256 $p) -ne $expected) {
                LogErr "  modified: $($op.path)"
                $bad++
            }
        }
        if ($bad -eq 0) {
            LogOk "Install matches expected old snapshot"
        } else {
            LogErr "$bad file(s) differ from expected"
            exit 1
        }
    } finally {
        if ($staging) { Remove-PathSafe $staging }
    }
}

if ($args.Count -eq 0) {
    Invoke-InteractiveMenu
    exit 0
}
$cmd  = $args[0]
$rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
$parsed = Read-Flags -ArgList $rest

try {
    switch ($cmd) {
        'create' {
            $outDir = Get-OptionalFlag $parsed.Flags 'out' '.'
            $bundle = Invoke-Create `
                -OldDir (Get-RequiredFlag $parsed.Flags 'old') `
                -NewDir (Get-RequiredFlag $parsed.Flags 'new') `
                -Game   (Get-RequiredFlag $parsed.Flags 'game') `
                -OldVer (Get-RequiredFlag $parsed.Flags 'old-ver') `
                -NewVer (Get-RequiredFlag $parsed.Flags 'new-ver') `
                -OutDir $outDir
            Write-Output $bundle
        }
        'apply' {
            Invoke-Apply `
                -PatchPath (Get-RequiredFlag $parsed.Flags 'patch') `
                -Target    (Get-RequiredFlag $parsed.Flags 'target') `
                -DryRun:($parsed.Flags.ContainsKey('dry-run')) `
                -NoBackup:($parsed.Flags.ContainsKey('no-backup')) `
                -KeepBackup:($parsed.Flags.ContainsKey('keep-backup'))
        }
        'restore' {
            $bk = Get-OptionalFlag $parsed.Flags 'backup' 'latest'
            Invoke-Restore `
                -Target     (Get-RequiredFlag $parsed.Flags 'target') `
                -Backup     $bk `
                -KeepBackup:($parsed.Flags.ContainsKey('keep-backup'))
        }
        'upload' {
            $creator = Get-OptionalFlag $parsed.Flags 'creator' 'anonymous'
            $desc    = Get-OptionalFlag $parsed.Flags 'description' 'Game patch generated by gpatcher'
            Invoke-IAUpload `
                -BundlePath (Get-RequiredFlag $parsed.Flags 'patch') `
                -Creator     $creator `
                -Description $desc
        }
        'search' {
            if ($parsed.Positional.Count -lt 1) { throw "search requires a game-name argument" }
            Invoke-IASearch -Query ($parsed.Positional -join ' ')
        }
        'fetch' {
            $outDir = Get-OptionalFlag $parsed.Flags 'out' '.'
            Invoke-IAFetch `
                -GameSlug (Get-RequiredFlag $parsed.Flags 'game') `
                -FromVer  (Get-RequiredFlag $parsed.Flags 'from') `
                -ToVer    (Get-RequiredFlag $parsed.Flags 'to') `
                -OutDir   $outDir
        }
        'verify' {
            Invoke-Verify `
                -Install (Get-RequiredFlag $parsed.Flags 'install') `
                -Against (Get-RequiredFlag $parsed.Flags 'against')
        }
        'doctor' { Invoke-Doctor }
        'ui' { Invoke-InteractiveMenu }
        'webui' {
            if (-not (Test-CommandExists 'node')) {
                throw "Node.js is required to run the web UI. Please install it from https://nodejs.org/"
            }
            $uiServer = Join-Path $PSScriptRoot 'ui\server.js'
            if (-not (Test-Path -LiteralPath $uiServer)) {
                throw "UI server file not found at $uiServer"
            }
            LogOk "Starting gpatcher web UI..."
            LogInfo "Opening http://localhost:3000 in your browser..."
            Start-Process "http://localhost:3000"
            node $uiServer
        }
        'update' {
            Invoke-Update -Force:($parsed.Flags.ContainsKey('force'))
        }
        'uninstall' {
            LogInfo "Uninstalling gpatcher..."
            $dirToRemove = if ($PSScriptRoot -match 'AppData\\Local\\gpatcher') { $PSScriptRoot } else { Join-Path $env:LOCALAPPDATA 'gpatcher' }
            
            # Remove from PATH
            $current = [System.Environment]::GetEnvironmentVariable('Path', 'User')
            $entries = $current -split ';' | Where-Object { $_ -ne '' -and $_ -ne $dirToRemove }
            $newPath = $entries -join ';'
            [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            LogOk "Removed gpatcher from user PATH"

            # Clean up files that are not currently locked
            $libDir = Join-Path $dirToRemove 'lib'
            $binDir = Join-Path $dirToRemove 'bin'
            if (Test-Path $libDir) { Remove-Item $libDir -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path $binDir) { Remove-Item $binDir -Recurse -Force -ErrorAction SilentlyContinue }

            LogInfo "To complete uninstallation, please restart your terminal and delete the folder:"
            Write-Host "  $dirToRemove" -ForegroundColor Yellow
        }
        'help'   { Show-Usage }
        default  { Show-Usage; exit 1 }
    }
} catch {
    LogErr $_.Exception.Message
    exit 1
}
