function Read-MenuSelection {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Options
    )

    # Check if we are running in an interactive host supporting RawUI
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
            Clear-Host
            Write-Host "=== $Title ===" -ForegroundColor Cyan
            Write-Host "Use Up/Down Arrow keys to select, Press Enter to confirm.`n" -ForegroundColor Gray

            for ($i = 0; $i -lt $Options.Count; $i++) {
                if ($i -eq $selectedIndex) {
                    Write-Host "  > [x] $($Options[$i])" -ForegroundColor Magenta
                } else {
                    Write-Host "    [ ] $($Options[$i])" -ForegroundColor Gray
                }
            }

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

    # Fallback to number entry for non-interactive host sessions
    Clear-Host
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  $($i + 1)) $($Options[$i])" -ForegroundColor Gray
    }
    Write-Host ""
    $valid = $false
    $choice = 0
    while (-not $valid) {
        Write-Host "Enter option (1-$($Options.Count)): " -NoNewline -ForegroundColor Cyan
        $val = Read-Host
        if ($val -match '^\d+$') {
            $num = [int]$val
            if ($num -ge 1 -and $num -le $Options.Count) {
                $choice = $num - 1
                $valid = $true
            }
        }
        if (-not $valid) {
            Write-Host "Invalid selection!" -ForegroundColor Red
        }
    }
    return $choice
}

function Read-TextInput {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default = ""
    )
    $display = if ($Default) { "${Prompt} [${Default}]: " } else { "${Prompt}: " }
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
        Write-Host "${Prompt}: " -NoNewline -ForegroundColor Cyan
        $val = Read-Host
        if (-not $val) {
            Write-Host "  Path cannot be empty!" -ForegroundColor Red
            continue
        }
        
        $resolved = $val
        try {
            $resolved = (Resolve-Path -LiteralPath $val -ErrorAction Stop).Path
        } catch {}

        if ($MustExist) {
            if (-not (Test-Path -LiteralPath $resolved)) {
                Write-Host "  Path does not exist: $resolved" -ForegroundColor Red
                continue
            }
            if ($IsDirectory -and -not (Test-Path -LiteralPath $resolved -PathType Container)) {
                Write-Host "  Path is not a directory!" -ForegroundColor Red
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
        $selection = Read-MenuSelection -Title "gpatcher CLI Dashboard" -Options $menuOptions
        
        Clear-Host
        switch ($selection) {
            0 { # Apply Patch
                Write-Host "=== Apply Game Patch ===" -ForegroundColor Cyan
                $patch = Read-TextInput -Prompt "Enter local patch ZIP path or download URL"
                $target = Read-PathInput -Prompt "Enter target game install directory" -MustExist -IsDirectory
                $dryRun = Read-ConfirmChoice -Prompt "Run as Dry Run (no file changes)?" -Default $false
                $noBackup = Read-ConfirmChoice -Prompt "Disable backup generation?" -Default $false
                $keepBackup = Read-ConfirmChoice -Prompt "Keep backup directory after successful apply?" -Default $true
                
                Write-Host "`nRunning apply operation..." -ForegroundColor Yellow
                try {
                    Invoke-Apply -PatchPath $patch -Target $target -DryRun:$dryRun -NoBackup:$noBackup -KeepBackup:$keepBackup
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            1 { # Create Patch
                Write-Host "=== Create Game Patch ===" -ForegroundColor Cyan
                $game = Read-TextInput -Prompt "Enter game title (e.g. Hades)"
                $oldVer = Read-TextInput -Prompt "Enter old version identifier"
                $newVer = Read-TextInput -Prompt "Enter new version identifier"
                $oldDir = Read-PathInput -Prompt "Enter old game directory" -MustExist -IsDirectory
                $newDir = Read-PathInput -Prompt "Enter new game directory" -MustExist -IsDirectory
                $outDir = Read-TextInput -Prompt "Enter output folder for patch ZIP" -Default "."
                
                Write-Host "`nRunning patch creation..." -ForegroundColor Yellow
                try {
                    $bundle = Invoke-Create -OldDir $oldDir -NewDir $newDir -Game $game -OldVer $oldVer -NewVer $newVer -OutDir $outDir
                    LogOk "Patch bundle created: $bundle"
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            2 { # Restore Backup
                Write-Host "=== Restore Patch Backup ===" -ForegroundColor Cyan
                $target = Read-PathInput -Prompt "Enter target game directory" -MustExist -IsDirectory
                $backup = Read-TextInput -Prompt "Enter backup directory name" -Default "latest"
                $keepBackup = Read-ConfirmChoice -Prompt "Keep backup folder after restore completes?" -Default $false
                
                Write-Host "`nRestoring backup..." -ForegroundColor Yellow
                try {
                    Invoke-Restore -Target $target -Backup $backup -KeepBackup:$keepBackup
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            3 { # Search & Fetch Patch
                Write-Host "=== Search Internet Archive ===" -ForegroundColor Cyan
                $query = Read-TextInput -Prompt "Enter game title to search"
                Write-Host "`nSearching..." -ForegroundColor Yellow
                try {
                    # Capture search output
                    $out = & (Join-Path $PSScriptRoot 'gpatcher.ps1') search $query 2>&1
                    $lines = $out -split "\n" | Where-Object { $_ -match 'Found: (gpatcher-\S+)' }
                    
                    if ($lines.Count -eq 0) {
                        Write-Host "No patches found for '$query'." -ForegroundColor Yellow
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
                            $outDir = Read-TextInput -Prompt "Enter output folder for downloaded patch" -Default "."
                            
                            # Parse tags to retrieveslug and versions
                            if ($selectedId -match 'gpatcher-([a-zA-Z0-9\-]+)-([a-zA-Z0-9\.\-]+)-to-([a-zA-Z0-9\.\-]+)') {
                                $slug = $Matches[1]
                                $from = $Matches[2]
                                $to = $Matches[3]
                                Write-Host "`nFetching patch $selectedId..." -ForegroundColor Yellow
                                Invoke-IAFetch -GameSlug $slug -FromVer $from -ToVer $to -OutDir $outDir
                            } else {
                                Write-Host "Invalid patch identifier format: $selectedId" -ForegroundColor Red
                            }
                        }
                    }
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            4 { # Verify Installation
                Write-Host "=== Verify Installation ===" -ForegroundColor Cyan
                $install = Read-PathInput -Prompt "Enter install directory to verify" -MustExist -IsDirectory
                $against = Read-PathInput -Prompt "Enter path to manifest.json or patch ZIP" -MustExist
                
                Write-Host "`nVerifying installation..." -ForegroundColor Yellow
                try {
                    Invoke-Verify -Install $install -Against $against
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            5 { # Diagnostics (Doctor)
                Write-Host "=== System Diagnostics ===" -ForegroundColor Cyan
                Invoke-Doctor
            }
            6 { # Check for updates
                Write-Host "=== Check for Updates ===" -ForegroundColor Cyan
                $force = Read-ConfirmChoice -Prompt "Force update check/re-install?" -Default $false
                try {
                    Invoke-Update -Force:$force
                } catch {
                    LogErr $_.Exception.Message
                }
            }
            7 { # Exit
                $running = $false
                Write-Host "Goodbye!" -ForegroundColor Green
                break
            }
        }

        if ($running) {
            Write-Host "`nPress any key to return to main menu..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
}
