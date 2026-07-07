# ============================================================
# bump_version.ps1 — Windows PowerShell equivalent of bump_version.sh
# ============================================================
# Bump project version across backend / frontend.
# Reads each component's current version from its source-of-truth
# file, writes the new version into all version-bearing files,
# syncs lockfiles via uv / npm, and verifies no stale refs remain.
#
# Usage:
#   .\bump_version.ps1 1.2.0
#   .\bump_version.ps1 patch
#   .\bump_version.ps1 1.2.0 --backend 1.1.5
#   .\bump_version.ps1 patch --frontend minor
#
# After running, commit/tag/push manually:
#   git add -A
#   git commit -m "..."
#   git tag -a vX.Y.Z -m "..."
#   git push origin main
#   git push origin vX.Y.Z
#
# ---------------------------------------------------------------
# TEMPLATE NOTE (shipped with the `fastapi-vue-version-bump` skill):
# Pre-configured for **2 components** — `backend` (Python/FastAPI · `uv lock`)
#   and `frontend` (Vue 3 · `npm install`). Default source-of-truth files
#   match each toolchain's convention (pyproject.toml / package.json).
# To add a third component, append a new hashtable entry to $Components and
#   extend the foreach switches below.
# To swap toolchains, edit each component's Sync scriptblock.
# ---------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Spec,

    [string]$Backend,
    [string]$Frontend,
)

$ErrorActionPreference = 'Stop'

# ── Locate repo root ──────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path "$ScriptDir\..").Path
Push-Location $RootDir

# ── Component definitions ─────────────────────────────────
$Components = @{
    backend   = @{
        Reader = { Select-String -Path "$RootDir\backend\pyproject.toml" -Pattern '^version\s*=\s*"(\d+\.\d+\.\d+)"' }
        Files  = @(
            @{ Path = "backend\pyproject.toml";             Mode = 'plain' },
            @{ Path = "backend\VERSION";                    Mode = 'plain' },
            @{ Path = "backend\app\main.py";                Mode = 'plain' },
            @{ Path = "backend\app\schemas\types.py";       Mode = 'plain' },
            @{ Path = "backend\app\api\endpoints\health.py"; Mode = 'plain' }
        )
        Sync   = { Push-Location "$RootDir\backend"; uv lock | Out-Null; Pop-Location }
    }
    frontend  = @{
        Reader = { Select-String -Path "$RootDir\frontend\package.json" -Pattern '"version"\s*:\s*"(\d+\.\d+\.\d+)"' }
        Files  = @(
            @{ Path = "frontend\package.json";       Mode = 'json' }
        )
        Sync   = { Push-Location "$RootDir\frontend"; npm install --silent --no-audit --no-fund | Out-Null; Pop-Location }
    }
}

# ── Helpers ───────────────────────────────────────────────

function Write-Info    { Write-Host "[INFO] $args" -ForegroundColor Cyan }
function Write-Success { Write-Host "[OK]   $args" -ForegroundColor Green }
function Write-Warn2   { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Err2    { Write-Host "[ERROR] $args" -ForegroundColor Red }

function Get-CurrentVersion {
    param([string]$Name, [hashtable]$Comp)
    $match = & $Comp.Reader | Select-Object -First 1
    if (-not $match) {
        Write-Err2 "could not read current version for $Name"
        exit 1
    }
    return $match.Matches[0].Groups[1].Value
}

function Resolve-TargetVersion {
    param(
        [string]$Spec,
        [string]$Current,
        [string]$Override
    )
    if ($Override) { return $Override }

    $kinds = @('patch', 'minor', 'major')
    if ($kinds -contains $Spec) {
        $parts = $Current.Split('.')
        switch ($Spec) {
            'patch' { return "$($parts[0]).$($parts[1]).$([int]$parts[2] + 1)" }
            'minor' { return "$($parts[0]).$([int]$parts[1] + 1).0" }
            'major' { return "$([int]$parts[0] + 1).0.0" }
        }
    }
    return $Spec
}

function Test-Semver {
    param([string]$V)
    return $V -match '^\d+\.\d+\.\d+$'
}

function Update-VersionInFile {
    param(
        [string]$Path,
        [string]$Old,
        [string]$New,
        [string]$Mode
    )
    if (-not (Test-Path $Path)) {
        Write-Warn2 "$Path (missing, skipped)"
        return
    }
    # Literal string substitution (.Replace is literal, not regex — no escaping needed)
    if ($Mode -eq 'json') {
        $pattern = "`"$Old`""
        $replacement = "`"$New`""
    } else {
        $pattern = $Old
        $replacement = $New
    }
    # Read bytes through .NET so we don't depend on the system default code page.
    # Get-Content in PS 5.x defaults to the OEM/ANSI code page, which mangles
    # UTF-8 multi-byte sequences (e.g. Chinese chars get decoded as mojibake).
    $utf8NoBom = New-Object System.Text.UTF8Encoding($False)
    $content = [System.IO.File]::ReadAllText($Path, $utf8NoBom)
    $content = $content.Replace($pattern, $replacement)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
    Write-Success "$Path"
}

# ── Validate spec ─────────────────────────────────────────

if (-not $Spec) {
    Write-Err2 "missing version spec: pass X.Y.Z or patch|minor|major"
    exit 1
}

$kinds = @('patch', 'minor', 'major')
$isKind = $kinds -contains $Spec
if (-not $isKind) {
    if (-not (Test-Semver $Spec)) {
        Write-Err2 "invalid version '$Spec' (expected X.Y.Z or patch|minor|major)"
        exit 1
    }
}

# ── Read current versions ─────────────────────────────────

Write-Info "resolving target versions"
$current = @{}
foreach ($name in @('backend', 'frontend')) {
    $current[$name] = Get-CurrentVersion -Name $name -Comp $Components[$name]
}

# ── Resolve targets ───────────────────────────────────────

$targets = @{}
foreach ($name in @('backend', 'frontend')) {
    $override = $null
    switch ($name) {
        'backend'   { $override = $Backend }
        'frontend'  { $override = $Frontend }
    }
    $targets[$name] = Resolve-TargetVersion -Spec $Spec -Current $current[$name] -Override $override
}

foreach ($name in @('backend', 'frontend')) {
    $t = $targets[$name]
    $c = $current[$name]
    if ($t -eq $c) {
        Write-Warn2 "  ${name}: already at $c (skip)"
    } else {
        Write-Host "  ${name}: $c -> $t" -ForegroundColor Cyan
    }
}

# ── Validate targets ──────────────────────────────────────

foreach ($name in @('backend', 'frontend')) {
    if (-not (Test-Semver $targets[$name])) {
        Write-Err2 "invalid resolved $name version '$($targets[$name])'"
        exit 1
    }
}

# ── Patch each component ─────────────────────────────────

$changed = $false
foreach ($name in @('backend', 'frontend')) {
    if ($targets[$name] -eq $current[$name]) { continue }
    $changed = $true
    Write-Info "patching $name ($($current[$name]) -> $($targets[$name]))"
    foreach ($f in $Components[$name].Files) {
        Update-VersionInFile -Path (Join-Path $RootDir $f.Path) -Old $current[$name] -New $targets[$name] -Mode $f.Mode
    }
    Write-Info "  syncing lockfile"
    try {
        & $Components[$name].Sync
        Write-Success "  lockfile refreshed"
    } catch {
        Write-Warn2 "  lockfile sync failed: $_"
    }
}

if (-not $changed) {
    Write-Success "no changes needed"
    Pop-Location
    exit 0
}

# ── Verify ────────────────────────────────────────────────

Write-Info "verifying"
$stale = $false
foreach ($name in @('backend', 'frontend')) {
    if ($targets[$name] -eq $current[$name]) { continue }
    # Search for stale version in any file under the component dir
    $hits = Select-String -Path (Join-Path $RootDir $name) -Pattern ([regex]::Escape($current[$name])) -SimpleMatch -ErrorAction SilentlyContinue
    # Filter out known-safe lockfile entries (uv.lock has many false positives)
    $realStale = $hits | Where-Object {
        $_.Path -notmatch 'package-lock\.json$' -and
        $_.Path -notmatch 'uv\.lock$'
    }
    if ($realStale) {
        Write-Err2 "stale references to $($current[$name]) in ${name}:"
        $realStale | ForEach-Object { Write-Host "    $($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
        $stale = $true
    }
}
if ($stale) { exit 1 }
Write-Success "no stale references"

# ── Diff summary ──────────────────────────────────────────

Write-Host ""
& git --no-pager diff --stat

# ── Suggested commit message ──────────────────────────────

$changedCount = 0
foreach ($name in @('backend', 'frontend')) {
    if ($targets[$name] -ne $current[$name]) { $changedCount++ }
}

$commitMsg = if ($changedCount -eq 2) {
    "chore: 升级版本到 v$($targets['backend'])"
} else {
    $parts = @()
    foreach ($name in @('backend', 'frontend')) {
        if ($targets[$name] -ne $current[$name]) {
            $parts += "($name`:$($current[$name])->$($targets[$name]))"
        }
    }
    "chore: 升级版本 $($parts -join ' ')"
}

Write-Host ""
Write-Info "next: review the diff above, then commit/tag/push manually:"
Write-Host "    git add -A"
Write-Host "    git commit -m `"$commitMsg`""
if ($changedCount -eq 2) {
    Write-Host "    git tag -a v$($targets['backend']) -m `"...`""
    Write-Host "    git push origin main"
    Write-Host "    git push origin v$($targets['backend'])"
}

Pop-Location