#requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root     = Split-Path -Parent $PSScriptRoot
$cli      = Join-Path $root 'gpatcher.ps1'
$fixtures = Join-Path $root 'tests\fixtures'
$v1       = Join-Path $fixtures 'v1'
$v2       = Join-Path $fixtures 'v2'
$tmp      = Join-Path $root 'tests\tmp'

function Reset-Fixtures {
    foreach ($p in @($v1, $v2, $tmp)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }

    # Helper: write file, creating parent dirs.
    function Put-File {
        param([string]$Path, [string]$Text)
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
    }

    # unchanged
    Put-File (Join-Path $v1 'static.txt') 'static content'
    Put-File (Join-Path $v2 'static.txt') 'static content'

    # modified small
    Put-File (Join-Path $v1 'data\config.ini') 'version=one'
    Put-File (Join-Path $v2 'data\config.ini') 'version=two and a bit longer'

    # added (v2 only)
    Put-File (Join-Path $v2 'new\added.txt') 'hello from v2'

    # deleted (v1 only)
    Put-File (Join-Path $v1 'old\removed.txt') 'goodbye'

    # binary modified
    $size = 256KB
    $rand = New-Object System.Random 42
    $buf1 = New-Object byte[] $size
    $rand.NextBytes($buf1)
    [System.IO.File]::WriteAllBytes((Join-Path $v1 'big.bin'), $buf1)

    $buf2 = New-Object byte[] $size
    [Array]::Copy($buf1, $buf2, $size)
    $patch = New-Object byte[] 4096
    (New-Object System.Random 99).NextBytes($patch)
    [Array]::Copy($patch, 0, $buf2, 100000, 4096)
    [System.IO.File]::WriteAllBytes((Join-Path $v2 'big.bin'), $buf2)
}

function Hash-Dir {
    param([string]$Dir)
    $full = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\','/')
    $files = Get-ChildItem -LiteralPath $full -Recurse -File | Sort-Object FullName
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($full.Length).TrimStart('\','/') -replace '\\','/'
            $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
            $line = "${rel}:$h`n"
            $b = [System.Text.Encoding]::UTF8.GetBytes($line)
            [void]$sha.TransformBlock($b, 0, $b.Length, $null, 0)
        }
        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        [System.BitConverter]::ToString($sha.Hash).Replace('-','').ToLower()
    } finally {
        $sha.Dispose()
    }
}

$passed = 0
$failed = 0

function Run-Test {
    param([string]$Name, [scriptblock]$Body)
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    try {
        & $Body
        Write-Host "PASS: $Name" -ForegroundColor Green
        $script:passed++
    } catch {
        Write-Host "FAIL: $Name -- $_" -ForegroundColor Red
        $script:failed++
        throw
    }
}

Run-Test 'Setup fixtures' { Reset-Fixtures }

Run-Test 'Create patch' {
    & $cli create --old $v1 --new $v2 --game 'Test Game' --old-ver '1' --new-ver '2' --out $tmp
    if ($LASTEXITCODE -ne 0) { throw "create failed (exit $LASTEXITCODE)" }
}

$bundle = Get-ChildItem -LiteralPath $tmp -Filter '*.patch.zip' | Select-Object -First 1
if (-not $bundle) { throw "No bundle produced in $tmp" }
Write-Host "Bundle: $($bundle.FullName) ($($bundle.Length) bytes)"

$work = Join-Path $tmp 'work'
Run-Test 'Copy v1 to workspace' {
    Copy-Item -LiteralPath $v1 -Destination $work -Recurse -Force
}

Run-Test 'Apply patch (no-backup)' {
    & $cli apply --patch $bundle.FullName --target $work --no-backup
    if ($LASTEXITCODE -ne 0) { throw "apply failed (exit $LASTEXITCODE)" }
}

Run-Test 'Hash-compare workspace vs v2' {
    $hWork = Hash-Dir $work
    $hV2   = Hash-Dir $v2
    Write-Host "  work=$hWork"
    Write-Host "  v2  =$hV2"
    if ($hWork -ne $hV2) { throw "Tree hash mismatch after apply" }
}

Run-Test 'Restore from backup undoes apply' {
    $workR = Join-Path $tmp 'work-restore'
    Copy-Item -LiteralPath $v1 -Destination $workR -Recurse -Force

    & $cli apply --patch $bundle.FullName --target $workR
    if ($LASTEXITCODE -ne 0) { throw "apply (with backup) failed (exit $LASTEXITCODE)" }

    $bk = @(Get-ChildItem -LiteralPath $workR -Filter '.gpatcher-backup-*' -Directory -Force)
    if ($bk.Count -eq 0) { throw "no backup dir was created" }
    Write-Host "  backup: $($bk[0].Name)"

    & $cli restore --target $workR
    if ($LASTEXITCODE -ne 0) { throw "restore failed (exit $LASTEXITCODE)" }

    $bk2 = @(Get-ChildItem -LiteralPath $workR -Filter '.gpatcher-backup-*' -Directory -Force -ErrorAction SilentlyContinue)
    if ($bk2.Count -ne 0) { throw "backup dir should have been removed after restore" }

    $hWork = Hash-Dir $workR
    $hV1   = Hash-Dir $v1
    Write-Host "  work=$hWork"
    Write-Host "  v1  =$hV1"
    if ($hWork -ne $hV1) { throw "restored tree != v1" }
}

Run-Test 'Restore --keep-backup retains backup dir' {
    $workK = Join-Path $tmp 'work-keep'
    Copy-Item -LiteralPath $v1 -Destination $workK -Recurse -Force
    & $cli apply --patch $bundle.FullName --target $workK
    if ($LASTEXITCODE -ne 0) { throw "apply failed" }
    & $cli restore --target $workK --keep-backup
    if ($LASTEXITCODE -ne 0) { throw "restore --keep-backup failed" }
    $bk = @(Get-ChildItem -LiteralPath $workK -Filter '.gpatcher-backup-*' -Directory -Force)
    if ($bk.Count -eq 0) { throw "backup dir should have been retained" }
}

Run-Test 'Tampered install fails pre-flight' {
    $work2 = Join-Path $tmp 'work2'
    Copy-Item -LiteralPath $v1 -Destination $work2 -Recurse -Force
    [System.IO.File]::WriteAllText((Join-Path $work2 'static.txt'), 'tampered', [System.Text.UTF8Encoding]::new($false))
    & $cli apply --patch $bundle.FullName --target $work2 --no-backup
    if ($LASTEXITCODE -eq 0) { throw "apply on tampered install should have failed" }
    # ensure no mutation: static.txt still 'tampered'
    $cur = [System.IO.File]::ReadAllText((Join-Path $work2 'static.txt'))
    if ($cur -ne 'tampered') { throw "Tampered file mutated despite pre-flight failure" }
}

Write-Host "`nResults: passed=$passed failed=$failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 } else { exit 0 }
