function Invoke-Apply {
    param(
        [Parameter(Mandatory)][string]$PatchPath,
        [Parameter(Mandatory)][string]$Target,
        [switch]$DryRun,
        [switch]$NoBackup
    )

    if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
        throw "Target dir not found: $Target"
    }

    $staging = New-TempDir 'gpatcher-apply'
    try {
        $patchLocal = $PatchPath
        if ($PatchPath -match '^https?://') {
            $patchLocal = Join-Path $staging 'patch.zip'
            LogInfo "Downloading: $PatchPath"
            Invoke-WebRequest -Uri $PatchPath -OutFile $patchLocal -UseBasicParsing
        }
        LogInfo "Unpacking patch"
        $unpacked = Join-Path $staging 'unpack'
        Expand-Dir -ZipPath $patchLocal -DestDir $unpacked

        $manifestPath = Join-Path $unpacked 'manifest.json'
        $m = Read-ManifestFile -Path $manifestPath
        LogInfo "$($m.game) $($m.old_version) -> $($m.new_version) ($($m.ops.Count) ops)"

        LogInfo "Pre-flight: verifying old install"
        $mismatch = New-Object System.Collections.Generic.List[string]
        foreach ($op in $m.ops) {
            $p = Join-Path $Target (ConvertTo-NativePath $op.path)
            $exists = Test-Path -LiteralPath $p
            if ($op.op -eq 'add') { continue }
            if (-not $exists) {
                $mismatch.Add("missing: $($op.path)")
                continue
            }
            $expected = $null
            switch ($op.op) {
                'keep'   { $expected = $op.sha256 }
                'diff'   { $expected = $op.old_sha256 }
                'delete' { $expected = $op.old_sha256 }
            }
            if ($expected) {
                if ((Get-FileSha256 $p) -ne $expected) {
                    $mismatch.Add("modified: $($op.path)")
                }
            }
        }
        if ($mismatch.Count -gt 0) {
            LogErr "Pre-flight failed:"
            $mismatch | ForEach-Object { LogErr "  $_" }
            throw "Wrong old version or tampered install. No changes made."
        }
        LogOk "Pre-flight passed"

        if ($DryRun) {
            LogInfo "Dry run -- no changes applied"
            return
        }

        $backupDir = $null
        if (-not $NoBackup) {
            $backupDir = Join-Path $Target ".gpatcher-backup-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            LogInfo "Backup: $backupDir"
            foreach ($op in $m.ops) {
                if ($op.op -eq 'diff' -or $op.op -eq 'delete') {
                    $src = Join-Path $Target (ConvertTo-NativePath $op.path)
                    $dst = Join-Path $backupDir (ConvertTo-NativePath $op.path)
                    New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
                    Copy-Item -LiteralPath $src -Destination $dst -Force
                }
            }
            # Stash a copy of the manifest inside the backup so `restore` can
            # also undo `add` ops (which leave no backed-up file behind).
            Write-ManifestFile -Manifest $m -Path (Join-Path $backupDir '.gpatcher-manifest.json')
        }

        try {
            foreach ($op in $m.ops) {
                $tgt = Join-Path $Target (ConvertTo-NativePath $op.path)
                switch ($op.op) {
                    'diff' {
                        $patchFile = Join-Path $unpacked (ConvertTo-NativePath $op.patch)
                        $tmpOut    = "$tgt.gpatcher-new"
                        Invoke-HPatchz -OldFile $tgt -PatchFile $patchFile -NewOut $tmpOut
                        if ((Get-FileSha256 $tmpOut) -ne $op.new_sha256) {
                            Remove-PathSafe $tmpOut
                            throw "Post-patch hash mismatch: $($op.path)"
                        }
                        Move-Item -LiteralPath $tmpOut -Destination $tgt -Force
                        LogInfo "patched: $($op.path)"
                    }
                    'add' {
                        $srcFile = Join-Path $unpacked (ConvertTo-NativePath $op.src)
                        New-Item -ItemType Directory -Path (Split-Path -Parent $tgt) -Force | Out-Null
                        Copy-Item -LiteralPath $srcFile -Destination $tgt -Force
                        if ((Get-FileSha256 $tgt) -ne $op.new_sha256) {
                            throw "Post-add hash mismatch: $($op.path)"
                        }
                        LogInfo "added:   $($op.path)"
                    }
                    'delete' {
                        Remove-Item -LiteralPath $tgt -Force
                        LogInfo "deleted: $($op.path)"
                    }
                    'keep' { }
                }
            }

            LogOk "Patch applied"
            if ($backupDir) {
                LogInfo "Backup retained at: $backupDir"
            }
        } catch {
            LogErr "Apply failed: $_"
            if ($backupDir -and (Test-Path -LiteralPath $backupDir)) {
                LogWarn "Rolling back from backup"
                Get-ChildItem -LiteralPath $backupDir -Recurse -File | ForEach-Object {
                    $rel = Get-RelPath -Root $backupDir -Full $_.FullName
                    $rt  = Join-Path $Target (ConvertTo-NativePath $rel)
                    New-Item -ItemType Directory -Path (Split-Path -Parent $rt) -Force | Out-Null
                    Copy-Item -LiteralPath $_.FullName -Destination $rt -Force
                }
                LogWarn "Rollback complete"
            }
            throw
        }
    } finally {
        Remove-PathSafe $staging
    }
}
