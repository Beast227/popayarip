function Invoke-Create {
    param(
        [Parameter(Mandatory)][string]$OldDir,
        [Parameter(Mandatory)][string]$NewDir,
        [Parameter(Mandatory)][string]$Game,
        [Parameter(Mandatory)][string]$OldVer,
        [Parameter(Mandatory)][string]$NewVer,
        [string]$OutDir = '.'
    )

    foreach ($d in @($OldDir, $NewDir)) {
        if (-not (Test-Path -LiteralPath $d -PathType Container)) {
            throw "Directory not found: $d"
        }
    }
    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }

    LogInfo "Hashing old install: $OldDir"
    $old = Get-FileTree -Root $OldDir
    LogInfo "Hashing new install: $NewDir"
    $new = Get-FileTree -Root $NewDir

    $oldMap = @{}
    foreach ($f in $old) { $oldMap[$f.RelPath] = $f }
    $newMap = @{}
    foreach ($f in $new) { $newMap[$f.RelPath] = $f }

    $staging = New-TempDir 'gpatcher-create'
    LogInfo "Staging: $staging"

    $diffDir = Join-Path $staging 'diff'
    $addDir  = Join-Path $staging 'add'
    New-Item -ItemType Directory -Path $diffDir -Force | Out-Null
    New-Item -ItemType Directory -Path $addDir  -Force | Out-Null

    $ops = New-Object System.Collections.Generic.List[object]

    $totalDiff = 0L
    $totalAdd  = 0L
    $countDiff = 0
    $countAdd  = 0
    $countDel  = 0
    $countKeep = 0

    foreach ($rel in $newMap.Keys) {
        $nf = $newMap[$rel]
        if ($oldMap.ContainsKey($rel)) {
            $of = $oldMap[$rel]
            if ($of.Sha256 -eq $nf.Sha256) {
                $ops.Add([pscustomobject]@{
                    op     = 'keep'
                    path   = $rel
                    sha256 = $nf.Sha256
                })
                $countKeep++
            } else {
                $patchRel  = "$rel.hdiff"
                $patchPath = Join-Path $diffDir (ConvertTo-NativePath $patchRel)
                New-Item -ItemType Directory -Path (Split-Path -Parent $patchPath) -Force | Out-Null
                $oldFull = Join-Path $OldDir (ConvertTo-NativePath $rel)
                $newFull = Join-Path $NewDir (ConvertTo-NativePath $rel)
                LogInfo "diff: $rel"
                Invoke-HDiffz -OldFile $oldFull -NewFile $newFull -PatchOut $patchPath
                $psize = (Get-Item -LiteralPath $patchPath).Length
                $totalDiff += $psize
                $ops.Add([pscustomobject]@{
                    op         = 'diff'
                    path       = $rel
                    old_sha256 = $of.Sha256
                    new_sha256 = $nf.Sha256
                    patch      = "diff/$patchRel"
                    patch_size = $psize
                })
                $countDiff++
            }
        } else {
            $dstPath = Join-Path $addDir (ConvertTo-NativePath $rel)
            New-Item -ItemType Directory -Path (Split-Path -Parent $dstPath) -Force | Out-Null
            $srcFull = Join-Path $NewDir (ConvertTo-NativePath $rel)
            Copy-Item -LiteralPath $srcFull -Destination $dstPath -Force
            LogInfo "add:  $rel"
            $totalAdd += $nf.Size
            $ops.Add([pscustomobject]@{
                op         = 'add'
                path       = $rel
                new_sha256 = $nf.Sha256
                src        = "add/$rel"
                size       = $nf.Size
            })
            $countAdd++
        }
    }
    foreach ($rel in $oldMap.Keys) {
        if (-not $newMap.ContainsKey($rel)) {
            LogInfo "del:  $rel"
            $ops.Add([pscustomobject]@{
                op         = 'delete'
                path       = $rel
                old_sha256 = $oldMap[$rel].Sha256
            })
            $countDel++
        }
    }

    $oldH = @{}
    foreach ($k in $oldMap.Keys) { $oldH[$k] = $oldMap[$k].Sha256 }
    $newH = @{}
    foreach ($k in $newMap.Keys) { $newH[$k] = $newMap[$k].Sha256 }
    $oldRoot = Get-MerkleRoot -PathHashMap $oldH
    $newRoot = Get-MerkleRoot -PathHashMap $newH

    $manifest = New-Manifest `
        -Game        $Game `
        -OldVersion  $OldVer `
        -NewVersion  $NewVer `
        -OldRootHash $oldRoot `
        -NewRootHash $newRoot `
        -Ops         $ops.ToArray()

    Write-ManifestFile -Manifest $manifest -Path (Join-Path $staging 'manifest.json')

    $slug   = Get-GameSlug $Game
    $bundle = Join-Path $OutDir "${slug}_${OldVer}_to_${NewVer}.patch.zip"
    LogInfo "Packing: $bundle"
    Compress-Dir -SrcDir $staging -ZipOut $bundle

    $bundleSize = (Get-Item -LiteralPath $bundle).Length

    LogOk "Bundle: $bundle"
    LogOk ("  size:    {0}" -f (Format-Bytes $bundleSize))
    LogOk ("  diff:    {0} files ({1})" -f $countDiff, (Format-Bytes $totalDiff))
    LogOk ("  add:     {0} files ({1})" -f $countAdd,  (Format-Bytes $totalAdd))
    LogOk ("  delete:  {0} files" -f $countDel)
    LogOk ("  keep:    {0} files" -f $countKeep)

    Remove-PathSafe $staging
    $bundle
}
