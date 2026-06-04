# gpatcher

Game patch producer/consumer for pre-installed game archives (e.g. steamrip releases).

Generate a small binary patch between two extracted game versions, share it via Internet Archive, and let anyone with the matching old install jump to the new version without re-downloading the full game.

## How it works

- Hashes both install dirs (SHA-256 per file).
- For files that changed, runs `hdiffz` to compute a binary diff.
- For files that were added, includes a raw copy.
- For files that were removed, records a delete instruction.
- Packs everything (`manifest.json` + `diff/` + `add/`) into a single `*.patch.zip`.
- `apply` re-runs hashes on the target, refuses to mutate anything if the old install does not match the expected hashes, then applies each operation and verifies the resulting hashes against the manifest.

## Setup & Installation (Windows)

### Global Installation (Recommended)

You can install `gpatcher` directly from any PowerShell terminal by running the following command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $z = Join-Path $env:TEMP "gpatcher-install.zip"; $d = Join-Path $env:TEMP "gpatcher-install-dir"; Invoke-WebRequest -Uri "https://github.com/Beast227/gpatcher/releases/download/v0.2/gpatcher-v0.2-win64.zip" -OutFile $z; Expand-Archive -Path $z -DestinationPath $d -Force; & (Join-Path $d "install.ps1"); Remove-Item $z -Force; Remove-Item $d -Recurse -Force'
```

*Alternatively, you can install manually:*

1. Download the latest `gpatcher-*-win64.zip` from the [GitHub Releases](https://github.com/Beast227/gpatcher/releases) page.
2. Extract the ZIP file to any directory.
3. Open a PowerShell terminal, navigate to the extracted folder, and run:
   ```powershell
   .\install.ps1
   ```
4. Restart your terminal, and verify the installation:
   ```powershell
   gpatcher doctor
   ```

To uninstall at any time, run:
```powershell
gpatcher uninstall
# or from the extracted folder:
.\install.ps1 -Uninstall
```

### Manual Setup (Developer Mode)

If you cloned the repository directly:

```powershell
# 1. Fetch the HDiffPatch binaries into bin\
.\tools\fetch-hdiffpatch.ps1

# 2. (optional, only for upload/search/fetch) install the ia CLI
pip install internetarchive
ia configure

# 3. sanity-check
.\gpatcher.ps1 doctor
```

## Usage

Running `gpatcher` with no arguments (or by double-clicking the cmd wrapper) launches the **Interactive TUI Dashboard**. You can also execute commands directly from the CLI:

```
gpatcher ui
gpatcher create  --old <dir> --new <dir> --game <name> --old-ver <v> --new-ver <v> [--out <dir>] [--exclude <patterns>]
gpatcher apply   --patch <path-or-url-or-dir> --target <install-dir> [--dry-run] [--no-backup] [--keep-backup]
gpatcher restore --target <install-dir> [--backup <dir-or-latest>] [--keep-backup]
gpatcher upload  --patch <bundle.zip> [--creator <name>] [--description <text>]
gpatcher search  <game-name>
gpatcher fetch   --game <slug> --from <v> --to <v> [--out <dir>]
gpatcher verify  --install <dir> --against <manifest-or-bundle>
gpatcher doctor
gpatcher update  [--force]
```

### Interactive TUI Dashboard

The dashboard provides a terminal interface with arrow key navigation to:
- Apply a game patch (with toggle options for Dry Run and Backups)
- Create a game patch with dynamic progress bars
- Restore from any local stashed backups
- Search & Fetch patch packages from the Internet Archive directly
- Verify a game folder integrity against any manifest snapshot
- Run system diagnostics (`doctor` check) and perform auto-updates


### Example: produce a patch

```powershell
.\gpatcher.ps1 create `
    --old "D:\Games\Hades_v1.38290" `
    --new "D:\Games\Hades_v1.38291" `
    --game "Hades" --old-ver 1.38290 --new-ver 1.38291 `
    --out  "D:\patches"
```

### Example: apply a patch

```powershell
.\gpatcher.ps1 apply `
    --patch "D:\patches\hades_1.38290_to_1.38291.patch.zip" `
    --target "D:\Games\Hades"
```

A backup of every file the patch will mutate is written to `<target>\.gpatcher-backup-<timestamp>\`. Pass `--no-backup` to skip it.

### Example: undo a patch with `restore`

```powershell
# undo the most recent apply on this install
.\gpatcher.ps1 restore --target "D:\Games\Hades"

# undo a specific backup (full path or name relative to target)
.\gpatcher.ps1 restore --target "D:\Games\Hades" --backup .gpatcher-backup-20260601153012

# undo but keep the backup dir around afterwards
.\gpatcher.ps1 restore --target "D:\Games\Hades" --keep-backup
```

`restore` walks the manifest stashed inside the backup dir, deletes files that `apply` had added, copies backed-up files back over modified/deleted ones, and verifies every restored file matches the original old-version hashes. The backup dir is removed by default after a successful restore; use `--keep-backup` to retain it.

Restore refuses to run if the target no longer matches the post-apply state recorded in the backup -- i.e. if files have been changed since the patch was applied -- so games that have been played and modified user-side won't be silently clobbered.

### Example: share via Internet Archive

```powershell
.\gpatcher.ps1 upload --patch "D:\patches\hades_1.38290_to_1.38291.patch.zip"
# others can then:
.\gpatcher.ps1 search hades
.\gpatcher.ps1 fetch --game hades --from 1.38290 --to 1.38291 --out .
```

## Constraints

- Windows-only (PowerShell 5.1+).
- Requires the matching *old* install on the consumer side. A patch from 1.0 to 1.2 does not apply to 1.1.
- First user to publish a patch still pays a full new-version download. The savings compound only as more users with the same old version pick up the patch.
- Symlinks / junctions inside the install dir are rejected; v0.2 does not preserve them.
- Trust model: there is no signing. The bundle SHA-256 is published in archive.org metadata but the uploader's identity is what you ultimately trust.

## Smoke test

```powershell
.\tests\smoke.ps1
```

Builds two synthetic install trees, creates a patch, applies it, hash-compares the result against the new tree, and verifies that pre-flight aborts on a tampered install.

## Manifest format (v1)

```json
{
  "schema": 1,
  "tool": "gpatcher 0.1",
  "game": "Hades",
  "game_slug": "hades",
  "old_version": "1.38290",
  "new_version": "1.38291",
  "created_utc": "2026-06-01T00:00:00Z",
  "old_root_sha256": "...",
  "new_root_sha256": "...",
  "ops": [
    {"op":"diff","path":"Hades.exe","old_sha256":"...","new_sha256":"...","patch":"diff/Hades.exe.hdiff","patch_size":12345},
    {"op":"add","path":"Content/New.pak","new_sha256":"...","src":"add/Content/New.pak","size":4096},
    {"op":"delete","path":"Content/Old.pak","old_sha256":"..."},
    {"op":"keep","path":"Engine/Static.dll","sha256":"..."}
  ]
}
```
