# scripts/test-patch-file.ps1 - regression test for Update-VersionInFile()
#
# Reproduces the "langchain>=0.4.0 also got rewritten" bug. Runs temp files
# through Update-VersionInFile, asserts results, cleans up.
#
# Usage: .\scripts\test-patch-file.ps1
#
# ASCII-only output to avoid PS 5.1 codepage issues with non-ASCII chars.

$ErrorActionPreference = 'Stop'

# Replica of Update-VersionInFile (kept in sync with bump_version.ps1).
function Update-VersionInFile {
    param(
        [string]$Path,
        [string]$Old,
        [string]$New,
        [string]$Mode
    )
    $oldEsc = [regex]::Escape($Old)
    switch ($Mode) {
        'json' {
            $pattern = '"version"\s*:\s*"' + $oldEsc + '"'
            $replacement = '"version": "' + $New + '"'
        }
        'toml' {
            $pattern = '^version\s*=\s*"' + $oldEsc + '"'
            $replacement = 'version = "' + $New + '"'
        }
        'python' {
            $pattern = '^(__version__)\s*=\s*"' + $oldEsc + '"'
            $replacement = '$1 = "' + $New + '"'
        }
        'plain' {
            $pattern = '^' + $oldEsc + '$'
            $replacement = $New
        }
        default {
            throw "unknown mode '$Mode'"
        }
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($False)
    $content = [System.IO.File]::ReadAllText($Path, $utf8NoBom)
    $content = [regex]::Replace($content, $pattern, $replacement, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

$TMPDIR = Join-Path $env:TEMP "patch-test-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $TMPDIR | Out-Null

$script:Pass = 0
$script:Fail = 0

function Assert-FileContains {
    param([string]$File, [string]$Needle, [string]$Desc)
    $content = [System.IO.File]::ReadAllText($File, [System.Text.UTF8Encoding]::new($false))
    if ($content -match [regex]::Escape($Needle)) {
        Write-Host "  [PASS] $Desc" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  [FAIL] $Desc (expected '$Needle' in $File)" -ForegroundColor Red
        Write-Host "    --- file content ---"
        Get-Content $File | ForEach-Object { Write-Host "      $_" }
        Write-Host "    --------------------"
        $script:Fail++
    }
}

function Assert-FileNotContains {
    param([string]$File, [string]$Needle, [string]$Desc)
    $content = [System.IO.File]::ReadAllText($File, [System.Text.UTF8Encoding]::new($false))
    if ($content -notmatch [regex]::Escape($Needle)) {
        Write-Host "  [PASS] $Desc" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  [FAIL] $Desc (did NOT expect '$Needle' in $File)" -ForegroundColor Red
        Write-Host "    --- file content ---"
        Get-Content $File | ForEach-Object { Write-Host "      $_" }
        Write-Host "    --------------------"
        $script:Fail++
    }
}

Write-Host "=== Test 1: pyproject.toml (toml mode) ===" -ForegroundColor Cyan
$pyproject = @'
[project]
name = "myapp"
version = "0.4.0"
dependencies = [
    "langchain>=0.4.0",
    "fastapi>=0.100.0",
    "pydantic~=0.4.0",
]
'@
$pyprojectPath = Join-Path $TMPDIR "pyproject.toml"
[System.IO.File]::WriteAllText($pyprojectPath, $pyproject, [System.Text.UTF8Encoding]::new($false))
Update-VersionInFile -Path $pyprojectPath -Old "0.4.0" -New "0.4.1" -Mode "toml"
Assert-FileContains     $pyprojectPath 'version = "0.4.1"' "version line updated"
Assert-FileNotContains $pyprojectPath 'langchain>=0.4.1' "langchain dep NOT changed"
Assert-FileContains     $pyprojectPath 'langchain>=0.4.0' "langchain dep preserved"
Assert-FileNotContains $pyprojectPath 'pydantic~=0.4.1' "pydantic dep NOT changed"
Assert-FileContains     $pyprojectPath 'pydantic~=0.4.0' "pydantic dep preserved"

Write-Host ""
Write-Host "=== Test 2: plain text VERSION file (plain mode) ===" -ForegroundColor Cyan
$versionPath = Join-Path $TMPDIR "VERSION"
[System.IO.File]::WriteAllText($versionPath, "0.4.0", [System.Text.UTF8Encoding]::new($false))
Update-VersionInFile -Path $versionPath -Old "0.4.0" -New "0.4.1" -Mode "plain"
$content = [System.IO.File]::ReadAllText($versionPath).Trim()
if ($content -eq "0.4.1") {
    Write-Host "  [PASS] VERSION file whole-line replaced with 0.4.1" -ForegroundColor Green
    $script:Pass++
} else {
    Write-Host "  [FAIL] VERSION file not updated (got '$content')" -ForegroundColor Red
    $script:Fail++
}

Write-Host ""
Write-Host "=== Test 3: Python __version__ (python mode) ===" -ForegroundColor Cyan
$pyContent = @'
"""My app module."""

__version__ = "0.4.0"

# Same-named variable should NOT be changed
SOME_DEP_VERSION = "0.4.0"
'@
$pyPath = Join-Path $TMPDIR "main.py"
[System.IO.File]::WriteAllText($pyPath, $pyContent, [System.Text.UTF8Encoding]::new($false))
Update-VersionInFile -Path $pyPath -Old "0.4.0" -New "0.4.1" -Mode "python"
Assert-FileContains     $pyPath '__version__ = "0.4.1"' "__version__ line updated"
Assert-FileNotContains $pyPath '__version__ = "0.4.0"' "old __version__ fully replaced"
Assert-FileContains     $pyPath 'SOME_DEP_VERSION = "0.4.0"' "other variable preserved"

Write-Host ""
Write-Host "=== Test 4: package.json (json mode) ===" -ForegroundColor Cyan
$jsonContent = @'
{
  "name": "myapp",
  "version": "0.4.0",
  "dependencies": {
    "react": "0.4.0",
    "vue": "3.0.0"
  }
}
'@
$jsonPath = Join-Path $TMPDIR "package.json"
[System.IO.File]::WriteAllText($jsonPath, $jsonContent, [System.Text.UTF8Encoding]::new($false))
Update-VersionInFile -Path $jsonPath -Old "0.4.0" -New "0.4.1" -Mode "json"
Assert-FileContains     $jsonPath '"version": "0.4.1"' "top-level version updated"
Assert-FileNotContains $jsonPath '"react": "0.4.1"' "react dep NOT changed"
Assert-FileContains     $jsonPath '"react": "0.4.0"' "react dep preserved"
Assert-FileContains     $jsonPath '"vue": "3.0.0"' "unrelated vue dep preserved"

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "PASS: $($script:Pass)" -ForegroundColor Green
Write-Host "FAIL: $($script:Fail)" -ForegroundColor $(if ($script:Fail -gt 0) { "Red" } else { "Green" })

# Cleanup
Remove-Item -LiteralPath $TMPDIR -Recurse -Force -ErrorAction SilentlyContinue

if ($script:Fail -gt 0) { exit 1 }
Write-Host "All tests passed." -ForegroundColor Green