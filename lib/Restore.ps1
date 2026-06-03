function Invoke-Restore {
    param(
        [Parameter(Mandatory)][string]$Target,
        [string]$Backup = 'latest',
        [switch]$KeepBackup
    )

    if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
        throw "Target dir not found: $Target"
    }

    $backupDir = $null
    if (-not $Backup -or $Backup -eq 'latest') {
        $candidates = @(Get-ChildItem -LiteralPath $Target -Filter '.gpatcher-backup-*' -Directory -Force |
                       Sort-Object Name -Descending)
        if ($candidates.Count -eq 0) {
            throw "No backup dirs found in $Target"
        }
        $backupDir = $candidates[0].FullName
    } elseif (Test-Path -LiteralPath $Backup -PathType Container) {
        $backupDir = (Resolve-Path -LiteralPath $Backup).Path
    } else {
        $maybe = Join-Path $Target $Backup
        if (Test-Path -LiteralPath $maybe -PathType Container) {
            $backupDir = (Resolve-Path -LiteralPath $maybe).Path
        } else {
            throw "Backup not found: $Backup"
        }
    }
    LogInfo "Backup: $backupDir"

    $manifestPath = Join-Path $backupDir '.gpatcher-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Backup is missing .gpatcher-manifest.json -- cannot restore (likely created before restore support)."
    }
    $m = Read-ManifestFile -Path $manifestPath
    LogInfo "Restoring $($m.game): $($m.new_version) -> $($m.old_version)"

    LogInfo "Pre-flight: verifying target looks patched"
    $mismatch = New-Object System.Collections.Generic.List[string]
    foreach ($op in $m.ops) {
        $p = Join-Path $Target (ConvertTo-NativePath $op.path)
        $exists = Test-Path -LiteralPath $p
        if ($op.op -eq 'diff' -or $op.op -eq 'add') {
            if (-not $exists) {
                $mismatch.Add("missing: $($op.path)")
            } elseif ((Get-FileSha256 $p) -ne $op.new_sha256) {
                $mismatch.Add("not-at-new-version: $($op.path)")
            }
        } elseif ($op.op -eq 'delete') {
            if ($exists) {
                $mismatch.Add("still-present: $($op.path)")
            }
        } elseif ($op.op -eq 'keep') {
            if (-not $exists) {
                $mismatch.Add("missing: $($op.path)")
            } elseif ((Get-FileSha256 $p) -ne $op.sha256) {
                $mismatch.Add("modified: $($op.path)")
            }
        }
    }
    if ($mismatch.Count -gt 0) {
        LogErr "Pre-flight failed -- target does not match the post-apply state recorded in backup:"
        $mismatch | ForEach-Object { LogErr "  $_" }
        throw "Target has changed since the patch was applied. No restore performed."
    }
    LogOk "Pre-flight passed"

    foreach ($op in $m.ops) {
        $tgt = Join-Path $Target (ConvertTo-NativePath $op.path)
        if ($op.op -eq 'add') {
            Remove-Item -LiteralPath $tgt -Force
            LogInfo "removed-add: $($op.path)"
        } elseif ($op.op -eq 'diff') {
            $src = Join-Path $backupDir (ConvertTo-NativePath $op.path)
            if (-not (Test-Path -LiteralPath $src)) {
                throw "Backup is missing file needed for restore: $($op.path)"
            }
            Copy-Item -LiteralPath $src -Destination $tgt -Force
            LogInfo "restored:    $($op.path)"
        } elseif ($op.op -eq 'delete') {
            $src = Join-Path $backupDir (ConvertTo-NativePath $op.path)
            if (-not (Test-Path -LiteralPath $src)) {
                throw "Backup is missing file needed for restore: $($op.path)"
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $tgt) -Force | Out-Null
            Copy-Item -LiteralPath $src -Destination $tgt -Force
            LogInfo "undeleted:   $($op.path)"
        }
        # keep: nothing to do
    }

    LogInfo "Post-flight: verifying old-version hashes"
    $bad = 0
    foreach ($op in $m.ops) {
        $expected = $null
        if ($op.op -eq 'diff')   { $expected = $op.old_sha256 }
        elseif ($op.op -eq 'delete') { $expected = $op.old_sha256 }
        elseif ($op.op -eq 'keep')   { $expected = $op.sha256 }
        if ($null -eq $expected) { continue }
        $p = Join-Path $Target (ConvertTo-NativePath $op.path)
        if (-not (Test-Path -LiteralPath $p)) {
            LogErr "  missing: $($op.path)"
            $bad++
            continue
        }
        if ((Get-FileSha256 $p) -ne $expected) {
            LogErr "  hash mismatch: $($op.path)"
            $bad++
        }
    }
    if ($bad -gt 0) {
        throw "$bad file(s) failed post-restore hash check. Backup kept at: $backupDir"
    }
    LogOk "Restored to $($m.old_version)"

    if (-not $KeepBackup) {
        Remove-PathSafe $backupDir
        LogInfo "Removed backup dir"
    } else {
        LogInfo "Backup retained: $backupDir"
    }
}
