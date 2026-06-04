function Get-DoctorCache {
    if ($null -eq $global:DoctorStatusCache) {
        $hdiffz  = Test-Path -LiteralPath (Get-BinPath 'hdiffz.exe')
        $hpatchz = Test-Path -LiteralPath (Get-BinPath 'hpatchz.exe')
        $python  = Test-CommandExists 'python'
        $global:DoctorStatusCache = @{
            hdiffz  = $hdiffz
            hpatchz = $hpatchz
            python  = $python
        }
    }
    return $global:DoctorStatusCache
}

function Clear-DoctorCache {
    $global:DoctorStatusCache = $null
}

function Draw-Header {
    Clear-Host
    Write-Host "  +--------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host "  |   ____ ____   _  _____ ____ _   _ _____ ____           |" -ForegroundColor Magenta
    Write-Host "  |  / ___|  _ \ / \|_   _/ ___| | | | ____|  _ \          |" -ForegroundColor Magenta
    Write-Host "  | | |  _| |_) / _ \ | | | |   | |_| |  _| | |_) |        |" -ForegroundColor Magenta
    Write-Host "  | | |_| |  __/ ___ \| | | |___|  _  | |___|  _ <         |" -ForegroundColor Magenta
    Write-Host "  |  \____|_| /_/   \_\_|  \____|_| |_|_____|_| \_\  v$global:GPATCHER_VERSION   |" -ForegroundColor Magenta
    Write-Host "  |                                                        |" -ForegroundColor Magenta
    Write-Host "  |            Game Delta Patching Dashboard               |" -ForegroundColor Gray
    Write-Host "  +--------------------------------------------------------+" -ForegroundColor Magenta

    $doc = Get-DoctorCache
    $hdiffzStr = if ($doc.hdiffz) { "[OK] hdiffz" } else { "[ERR] hdiffz" }
    $hpatchzStr = if ($doc.hpatchz) { "[OK] hpatchz" } else { "[ERR] hpatchz" }
    $pythonStr = if ($doc.python) { "[OK] python" } else { "[ERR] python" }

    $hdiffzColor = if ($doc.hdiffz) { "Green" } else { "Red" }
    $hpatchzColor = if ($doc.hpatchz) { "Green" } else { "Red" }
    $pythonColor = if ($doc.python) { "Green" } else { "Yellow" }

    Write-Host "  [ Status ]  " -NoNewline -ForegroundColor Gray
    Write-Host "$hdiffzStr  " -NoNewline -ForegroundColor $hdiffzColor
    Write-Host "|  " -NoNewline -ForegroundColor DarkGray
    Write-Host "$hpatchzStr  " -NoNewline -ForegroundColor $hpatchzColor
    Write-Host "|  " -NoNewline -ForegroundColor DarkGray
    Write-Host $pythonStr -ForegroundColor $pythonColor
    Write-Host ""
}

function Draw-BoxTop {
    param([string]$Title)
    $line = "-- $Title " + ("-" * (54 - $Title.Length))
    Write-Host "  +$line+" -ForegroundColor Cyan
}

function Draw-BoxBottom {
    Write-Host "  +" + ("-" * 56) + "+" -ForegroundColor Cyan
}

function Read-MenuSelection {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Options
    )

    $interactive = $true
    try {
        $null = $Host.UI.RawUI.KeyAvailable
    } catch {
        $interactive = $false
    }

    if ($interactive) {
        $selectedIndex = 0
        $running = $true

        while ($running) {
            Draw-Header
            Draw-BoxTop -Title $Title
            
            for ($i = 0; $i -lt $Options.Count; $i++) {
                if ($i -eq $selectedIndex) {
                    $optText = "  >  [ $($Options[$i]) ]"
                    $padded = $optText.PadRight(56)
                    Write-Host "  |" -NoNewline -ForegroundColor Cyan
                    Write-Host $padded -NoNewline -BackgroundColor DarkMagenta -ForegroundColor White
                    Write-Host "|" -ForegroundColor Cyan
                } else {
                    $optText = "     [ $($Options[$i]) ]"
                    $padded = $optText.PadRight(56)
                    Write-Host "  |" -NoNewline -ForegroundColor Cyan
                    Write-Host $padded -NoNewline -ForegroundColor Gray
                    Write-Host "|" -ForegroundColor Cyan
                }
            }
            
            Draw-BoxBottom

            try {
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                switch ($key.VirtualKeyCode) {
                    38 { # Up Arrow
                        $selectedIndex = ($selectedIndex - 1 + $Options.Count) % $Options.Count
                    }
                    40 { # Down Arrow
                        $selectedIndex = ($selectedIndex + 1) % $Options.Count
                    }
                    13 { # Enter
                        $running = $false
                    }
                }
            } catch {
                $interactive = $false
                $running = $false
            }
        }
        if ($interactive) {
            return $selectedIndex
        }
    }

    # Non-interactive fallback
    Draw-Header
    Draw-BoxTop -Title $Title
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $optText = "   $($i + 1)) $($Options[$i])"
        $padded = $optText.PadRight(56)
        Write-Host "  |$padded|" -ForegroundColor Cyan
    }
    Draw-BoxBottom
    Write-Host ""
    
    $valid = $false
    $choice = 0
    while (-not $valid) {
        Write-Host "  > Enter option (1-$($Options.Count)): " -NoNewline -ForegroundColor Cyan
        $val = Read-Host
        if ($val -match '^\d+$') {
            $num = [int]$val
            if ($num -ge 1 -and $num -le $Options.Count) {
                $choice = $num - 1
                $valid = $true
            }
        }
        if (-not $valid) {
            Write-Host "  [err] Invalid selection!" -ForegroundColor Red
        }
    }
    return $choice
}

function Read-TextInput {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default = ""
    )
    $display = if ($Default) { "  | > ${Prompt} [${Default}]: " } else { "  | > ${Prompt}: " }
    Write-Host $display -NoNewline -ForegroundColor Cyan
    $val = Read-Host
    if (-not $val) { $val = $Default }
    $val
}

function Read-PathInput {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$MustExist,
        [switch]$IsDirectory
    )
    $valid = $false
    $resolved = ""
    while (-not $valid) {
        Write-Host "  | > ${Prompt}: " -NoNewline -ForegroundColor Cyan
        $val = Read-Host
        if (-not $val) {
            Write-Host "  |   [err] Path cannot be empty!" -ForegroundColor Red
            continue
        }
        
        $resolved = $val
        try {
            $resolved = (Resolve-Path -LiteralPath $val -ErrorAction Stop).Path
        } catch {}

        if ($MustExist) {
            if (-not (Test-Path -LiteralPath $resolved)) {
                Write-Host "  |   [err] Path does not exist: $resolved" -ForegroundColor Red
                continue
            }
            if ($IsDirectory -and -not (Test-Path -LiteralPath $resolved -PathType Container)) {
                Write-Host "  |   [err] Path is not a directory!" -ForegroundColor Red
                continue
            }
        }
        $valid = $true
    }
    $resolved
}

function Read-ConfirmChoice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $true
    )
    $opt = if ($Default) { "(Y/n)" } else { "(y/N)" }
    $choice = Read-MenuSelection -Title "$Prompt $opt" -Options @("Yes", "No")
    return ($choice -eq 0)
}

function Invoke-InteractiveMenu {
    $menuOptions = @(
        "Apply a game patch",
        "Create a game patch",
        "Restore from a backup",
        "Search & Fetch patch from Internet Archive",
        "Verify an installation",
        "System diagnostics check (doctor)",
        "Check for updates",
        "Exit"
    )

    $running = $true
    while ($running) {
        $selection = Read-MenuSelection -Title "Select Operation" -Options $menuOptions
        
        Clear-Host
        Draw-Header
        Write-Host ""
        
        switch ($selection) {
            0 { # Apply Patch
                Draw-BoxTop -Title "Apply Game Patch"
                $patch = Read-TextInput -Prompt "Enter local patch ZIP path or URL"
                $target = Read-PathInput -Prompt "Enter target game directory" -MustExist -IsDirectory
                Draw-BoxBottom
                
                $dryRun = Read-ConfirmChoice -Prompt "Run as Dry Run (no file changes)?" -Default $false
                $noBackup = Read-ConfirmChoice -Prompt "Disable backup generation?" -Default $false
                $keepBackup = Read-ConfirmChoice -Prompt "Keep backup directory after successful apply?" -Default $true
                
                Write-Host "`n  > Running apply operation..." -ForegroundColor Yellow
                try {
                    Invoke-Apply -PatchPath $patch -Target $target -DryRun:$dryRun -NoBackup:$noBackup -KeepBackup:$keepBackup
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            1 { # Create Patch
                Draw-BoxTop -Title "Create Game Patch"
                $game = Read-TextInput -Prompt "Enter game title (e.g. Hades)"
                $oldVer = Read-TextInput -Prompt "Enter old version"
                $newVer = Read-TextInput -Prompt "Enter new version"
                $oldDir = Read-PathInput -Prompt "Enter old game directory" -MustExist -IsDirectory
                $newDir = Read-PathInput -Prompt "Enter new game directory" -MustExist -IsDirectory
                $outDir = Read-TextInput -Prompt "Enter output folder" -Default "."
                $customEx = Read-TextInput -Prompt "Custom excludes (e.g. Mods/*,*.bak) [Optional]"
                Draw-BoxBottom

                $excludes = @()
                if ($customEx) {
                    $excludes = $customEx -split '[,;]' | ForEach-Object { $_.Trim() }
                }
                
                Write-Host "`n  > Running patch creation..." -ForegroundColor Yellow
                try {
                    $bundle = Invoke-Create -OldDir $oldDir -NewDir $newDir -Game $game -OldVer $oldVer -NewVer $newVer -OutDir $outDir -Exclude $excludes
                    LogOk "Patch bundle created: $bundle"
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            2 { # Restore Backup
                Draw-BoxTop -Title "Restore Patch Backup"
                $target = Read-PathInput -Prompt "Enter target game directory" -MustExist -IsDirectory
                $backup = Read-TextInput -Prompt "Enter backup name" -Default "latest"
                Draw-BoxBottom

                $keepBackup = Read-ConfirmChoice -Prompt "Keep backup folder after restore completes?" -Default $false
                
                Write-Host "`n  > Restoring backup..." -ForegroundColor Yellow
                try {
                    Invoke-Restore -Target $target -Backup $backup -KeepBackup:$keepBackup
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            3 { # Search & Fetch Patch
                Draw-BoxTop -Title "Search Internet Archive"
                $query = Read-TextInput -Prompt "Enter game title to search"
                Draw-BoxBottom

                Write-Host "`n  > Searching..." -ForegroundColor Yellow
                try {
                    $out = & (Join-Path $PSScriptRoot 'gpatcher.ps1') search $query 2>&1
                    $lines = $out -split "\n" | Where-Object { $_ -match 'Found: (gpatcher-\S+)' }
                    
                    if ($lines.Count -eq 0) {
                        Write-Host "  [warn] No patches found for '$query'." -ForegroundColor Yellow
                    } else {
                        $identifiers = @()
                        $options = @()
                        foreach ($line in $lines) {
                            if ($line -match 'Found: (\S+)') {
                                $id = $Matches[1]
                                $identifiers += $id
                                $options += $id
                            }
                        }
                        $options += "Cancel"
                        
                        $selectIdx = Read-MenuSelection -Title "Select Patch to Fetch" -Options $options
                        if ($selectIdx -lt $identifiers.Count) {
                            $selectedId = $identifiers[$selectIdx]
                            Draw-BoxTop -Title "Fetch Selected Patch"
                            $outDir = Read-TextInput -Prompt "Enter output folder" -Default "."
                            Draw-BoxBottom
                            
                            if ($selectedId -match 'gpatcher-([a-zA-Z0-9\-]+)-([a-zA-Z0-9\.\-]+)-to-([a-zA-Z0-9\.\-]+)') {
                                $slug = $Matches[1]
                                $from = $Matches[2]
                                $to = $Matches[3]
                                Write-Host "`n  > Fetching patch $selectedId..." -ForegroundColor Yellow
                                Invoke-IAFetch -GameSlug $slug -FromVer $from -ToVer $to -OutDir $outDir
                            } else {
                                Write-Host "  [err] Invalid patch identifier format: $selectedId" -ForegroundColor Red
                            }
                        }
                    }
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            4 { # Verify Installation
                Draw-BoxTop -Title "Verify Installation"
                $install = Read-PathInput -Prompt "Enter install directory" -MustExist -IsDirectory
                $against = Read-PathInput -Prompt "Enter manifest.json or patch ZIP path" -MustExist
                Draw-BoxBottom
                
                Write-Host "`n  > Verifying installation..." -ForegroundColor Yellow
                try {
                    Invoke-Verify -Install $install -Against $against
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            5 { # Diagnostics (Doctor)
                Draw-BoxTop -Title "System Diagnostics"
                Draw-BoxBottom
                Invoke-Doctor
                Clear-DoctorCache # Force refresh diagnostic cache next time
            }
            6 { # Check for updates
                $force = Read-ConfirmChoice -Prompt "Force update check/re-install?" -Default $false
                Write-Host "`n  > Checking for updates..." -ForegroundColor Yellow
                try {
                    Invoke-Update -Force:$force
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            7 { # Exit
                $running = $false
                Write-Host "  > Goodbye!" -ForegroundColor Green
                break
            }
        }

        if ($running) {
            Write-Host "`n  Press any key to return to main menu..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
}
