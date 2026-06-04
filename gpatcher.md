# gpatcher.md — gpatcher project context

## What is this project?

**gpatcher** is a Windows-only PowerShell (5.1+) CLI tool that produces and consumes binary delta patches for pre-installed game archives (e.g. steamrip releases). It lets someone with an older extracted game install upgrade to a newer version by downloading a small patch instead of re-downloading the entire game.

Patches are optionally shared via Internet Archive (`archive.org`).

## High-level workflow

1. **`create`** — Hash two game install directories (old & new), compute binary diffs with HDiffPatch (`hdiffz`), collect added files, record deleted files, and pack everything into a `*.patch.zip` bundle containing `manifest.json`, `diff/`, and `add/` directories.
2. **`apply`** — Verify the target install matches the expected old-version hashes (pre-flight), optionally back up files that will change, apply diffs (`hpatchz`), copy added files, delete removed files, and verify post-apply hashes.
3. **`restore`** — Undo a previously applied patch using the backup directory created during `apply`. Verifies the target still matches the post-apply state before restoring, then verifies old-version hashes after restoring.
4. **`upload`/`search`/`fetch`** — Publish patch bundles to Internet Archive, search for existing patches, and download them. These require the `ia` CLI (`pip install internetarchive`).
5. **`verify`** — Check an install directory against a manifest or bundle to see if it matches the expected old-version snapshot.
6. **`doctor`** — Sanity-check that required tools (`hdiffz.exe`, `hpatchz.exe`, `python`, `ia`) are available.
7. **`update`** — Automatically check for updates and update the gpatcher files by downloading the latest release from GitHub.

## Project structure

```
gpatcher/
├── gpatcher.ps1          # Main CLI entry point — argument parsing, command dispatch
├── lib/
│   ├── Common.ps1         # Logging (LogInfo/Warn/Err/Ok), path utilities, temp dirs, Format-Bytes, Assert-NotReparse, version constant
│   ├── Hash.ps1           # Get-FileSha256 (per-file SHA-256), Get-MerkleRoot (deterministic root hash of a file tree)
│   ├── Walk.ps1           # Get-FileTree — recursive file enumeration with hashing + progress bar
│   ├── Diff.ps1           # Invoke-HDiffz / Invoke-HPatchz wrappers for bin/hdiffz.exe and bin/hpatchz.exe
│   ├── Manifest.ps1       # Get-GameSlug, New-Manifest, Write-ManifestFile, Read-ManifestFile
│   ├── Archive.ps1        # Compress-Dir / Expand-Dir — ZIP helpers via System.IO.Compression
│   ├── Create.ps1         # Invoke-Create — patch bundle creation logic
│   ├── Apply.ps1          # Invoke-Apply — patch application with pre-flight verification, backup, and rollback
│   ├── Restore.ps1        # Invoke-Restore — undo an applied patch from backup
│   ├── IA.ps1             # Invoke-IAUpload / Invoke-IASearch / Invoke-IAFetch — Internet Archive integration
│   ├── Update.ps1         # Invoke-Update — automatically update gpatcher from GitHub releases
│   └── Interactive.ps1    # Invoke-InteractiveMenu — interactive console dashboard UI (TUI)
├── bin/
│   ├── hdiffz.exe         # Binary diff tool (from HDiffPatch, fetched by tools/fetch-hdiffpatch.ps1)
│   └── hpatchz.exe        # Binary patch tool (from HDiffPatch)
├── tools/
│   └── fetch-hdiffpatch.ps1  # Downloads latest HDiffPatch win64 release from GitHub into bin/
├── tests/
│   ├── smoke.ps1          # Integration smoke test — synthetic fixtures, create → apply → verify → restore → tamper check
│   ├── fixtures/          # Generated test fixtures (v1/, v2/ — gitignored)
│   └── tmp/               # Temp test output (gitignored)
├── .gitignore
└── README.md
```

## Key conventions

- **Language**: Pure PowerShell 5.1+, no external modules. `Set-StrictMode -Version 3.0` and `$ErrorActionPreference = 'Stop'` everywhere.
- **Dot-sourcing**: `gpatcher.ps1` dot-sources all `lib/*.ps1` files at startup. The lib files are not standalone modules.
- **Path handling**: All manifest paths use forward slashes (`/`). `ConvertTo-NativePath` converts them to backslashes for Windows filesystem operations. `Get-RelPath` produces forward-slash relative paths from a root.
- **Hashing**: SHA-256 everywhere. `Get-FileSha256` returns lowercase hex. `Get-MerkleRoot` computes a deterministic root hash over sorted `path:hash\n` lines.
- **Error handling**: Functions `throw` on failure. The main script catches at the top level, logs via `LogErr`, and exits with code 1.
- **Logging**: Colored console output via `LogInfo` (cyan), `LogWarn` (yellow), `LogErr` (red), `LogOk` (green). No file logging.
- **Temp directories**: Created via `New-TempDir` with a GUID suffix in `$env:TEMP`, always cleaned up in `finally` blocks.
- **No symlinks**: `Assert-NotReparse` rejects symlinks/junctions during file tree walks.

## Manifest format (schema v1)

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
    {"op":"diff",   "path":"...", "old_sha256":"...", "new_sha256":"...", "patch":"diff/...", "patch_size":...},
    {"op":"add",    "path":"...", "new_sha256":"...", "src":"add/...", "size":...},
    {"op":"delete", "path":"...", "old_sha256":"..."},
    {"op":"keep",   "path":"...", "sha256":"..."}
  ]
}
```

## Backup mechanism

- `apply` creates `.gpatcher-backup-<yyyyMMddHHmmss>/` inside the target directory.
- Backed-up files: those touched by `diff` and `delete` ops.
- A copy of the manifest is stashed as `.gpatcher-manifest.json` inside the backup dir.
- On apply failure, automatic rollback copies backed-up files back.
- `restore` uses the stashed manifest to fully undo the patch, then verifies old-version hashes.
- `restore` refuses to run if the target has been modified since the patch was applied.

## Internet Archive integration

- Item identifier format: `gpatcher-<slug>-<oldver>-to-<newver>` (max 100 chars).
- Subjects: `gpatcher`, `popayarip`, `game-patch`, `<slug>`, `version-<old>`, `version-<new>`.
- Requires `ia` CLI tool (`pip install internetarchive` + `ia configure`).

## External dependency

- **HDiffPatch** (`hdiffz.exe` / `hpatchz.exe`) — binary delta tool from [github.com/sisong/HDiffPatch](https://github.com/sisong/HDiffPatch). Fetched via `tools/fetch-hdiffpatch.ps1`. The `-f` flag is used for both diff and patch operations (force overwrite).

## Testing

- Single smoke test at `tests/smoke.ps1`. Run with `.\tests\smoke.ps1`.
- Creates synthetic v1/v2 fixtures (text files, binary files with partial changes).
- Test cases: create patch → apply (no-backup) → hash-compare result vs v2 → apply (with backup) → restore → verify restored = v1 → keep-backup flag → tampered install rejects pre-flight.

## Current limitations / known constraints

- Windows-only (PowerShell 5.1+).
- Exact version matching required — a patch from v1.0→v1.2 cannot apply to v1.1.
- No code signing or cryptographic identity — trust is based on the uploader's archive.org account.
- Symlinks and junctions are rejected.
- Tool version is defined in the `$GPATCHER_VERSION` variable in `lib/Common.ps1`.
