# =============================================================================
# Smash for Sydney - Windows Setup Script  (PowerShell)
# =============================================================================
# Sets up everything to run the Smash for Sydney bot framework on a fresh
# Windows (x64) install. Idempotent - safe to re-run.
#
# What this does:
#   1. Verifies Python 3 / py launcher
#   2. Downloads the Slippi Dolphin Windows build (Ishiiruka) from GitHub
#   3. Extracts Slippi Dolphin.exe + Sys into a 'netplay\' dir
#      (libmelee requires the SLIPPI_PATH to contain 'netplay')
#      (libmelee's non-mainline Windows exe name is 'Slippi Dolphin.exe')
#   4. Creates a User\ dir next to the exe (libmelee's Windows home path)
#   5. Creates the Melee ISO folder
#   6. Creates a Python virtualenv and installs the `melee` library
#   7. Writes env.ps1 with SLIPPI_PATH / SMASH_ISO_PATH
#
# After running: download the Melee ISO into $HOME\Documents\Melee\melee.iso
# then:  . .\env.ps1 ; .\.venv\Scripts\python.exe arena.py
#
# Manual step: download the Super Smash Bros. Melee ISO and place at
#   $HOME\Documents\Melee\melee.iso   (or edit SMASH_ISO_PATH in env.ps1)
#   ISO link: https://drive.google.com/file/d/1H9QNNFmVpZLys_kMJq44dpkv7EKBQqHZ/view
# =============================================================================

# -----------------------------------------------------------------------------
# Config (edit these if you want different locations)
# -----------------------------------------------------------------------------
$ErrorActionPreference = "Stop"

$SlippiVersion   = "3.6.4"
$SlippiZipUrl    = "https://github.com/project-slippi/Ishiiruka/releases/download/v$SlippiVersion/FM-Slippi-$SlippiVersion-Win.zip"
$InstallDir      = "$HOME\slippi-dolphin\netplay"        # must contain 'netplay'
$DolphinHome     = Join-Path $InstallDir "User"          # libmelee Windows home path
$IsoDir          = "$HOME\Documents\Melee"
$IsoPath         = Join-Path $IsoDir "melee.iso"
$RepoDir         = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvDir         = Join-Path $RepoDir ".venv"

Write-Host "=== Smash for Sydney Windows Setup ==="
Write-Host "Repo:        $RepoDir"
Write-Host "Venv:        $VenvDir"
Write-Host "Slippi dir:  $InstallDir"
Write-Host "Dolphin home:$DolphinHome"
Write-Host "ISO:         $IsoPath"
Write-Host ""

# -----------------------------------------------------------------------------
# Helper: find the python executable (prefer py launcher, then python)
# -----------------------------------------------------------------------------
function Find-Python {
    foreach ($cmd in @("py", "python", "python3")) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            try {
                $ver = & $found --version 2>&1
                if ($ver -match "^Python 3\.") {
                    return $found.Source
                }
            } catch {}
        }
    }
    return $null
}

# -----------------------------------------------------------------------------
# 1. Python 3
# -----------------------------------------------------------------------------
Write-Host "[1/7] Checking Python..."
$PythonExe = Find-Python
if (-not $PythonExe) {
    Write-Host "ERROR: Python 3 not found."
    Write-Host "  Install from https://www.python.org/downloads/"
    Write-Host "  (tick 'Add Python to PATH' in the installer,"
    Write-Host "   and include the optional 'pip' + 'py launcher' features)"
    exit 1
}
Write-Host "      $(& $PythonExe --version)  done"

# -----------------------------------------------------------------------------
# 2. Download + extract Slippi Dolphin (Windows zip)
# -----------------------------------------------------------------------------
$DolphinExe = Join-Path $InstallDir "Slippi Dolphin.exe"
Write-Host "[2/7] Downloading + extracting Slippi Dolphin v$SlippiVersion (Windows)..."
if (Test-Path $DolphinExe) {
    Write-Host "      already extracted. skipping."
} else {
    $tmpZip = Join-Path $env:TEMP "slippi-win.zip"
    # Windows 10+ ships with curl.exe; fall back to .NET WebClient
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        curl.exe -fsSL -o $tmpZip $SlippiZipUrl
    } else {
        (New-Object System.Net.WebClient).DownloadFile($SlippiZipUrl, $tmpZip)
    }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $InstallDir -Force
    Remove-Item $tmpZip -Force
    Write-Host "      extracted -> $InstallDir"
}

# -----------------------------------------------------------------------------
# 3. Verify the exe exists (libmelee expects this exact name)
# -----------------------------------------------------------------------------
Write-Host "[3/7] Verifying Slippi Dolphin.exe..."
if (-not (Test-Path $DolphinExe)) {
    Write-Host "ERROR: expected exe not found at $DolphinExe"
    Write-Host "       Contents of $InstallDir :"
    Get-ChildItem $InstallDir | Select-Object -First 10
    exit 1
}
Write-Host "      $DolphinExe  done"

# -----------------------------------------------------------------------------
# 4. Dolphin home ($InstallDir\User\)
# libmelee checks '$path/User/' on Windows (no explicit Windows branch),
# so the User dir must live next to the exe.
# -----------------------------------------------------------------------------
Write-Host "[4/7] Setting up Dolphin home ($DolphinHome)..."
New-Item -ItemType Directory -Force -Path $DolphinHome | Out-Null
# Windows uses named pipes (\\.\pipe\slippibot{port}) - no Pipes dir needed.
Write-Host "      ready  done"

# -----------------------------------------------------------------------------
# 5. ISO folder
# -----------------------------------------------------------------------------
Write-Host "[5/7] Creating ISO folder: $IsoDir"
New-Item -ItemType Directory -Force -Path $IsoDir | Out-Null
if (Test-Path $IsoPath) {
    Write-Host "      ISO found: $IsoPath  done"
} else {
    Write-Host "      No ISO yet. Download and place at:"
    Write-Host "           $IsoPath"
    Write-Host "           https://drive.google.com/file/d/1H9QNNFmVpZLys_kMJq44dpkv7EKBQqHZ/view"
}

# -----------------------------------------------------------------------------
# 6. Virtualenv + melee library
# -----------------------------------------------------------------------------
Write-Host "[6/7] Creating venv and installing melee..."
if (-not (Test-Path $VenvDir)) {
    & $PythonExe -m venv $VenvDir
}
$VenvPip    = Join-Path $VenvDir "Scripts\pip.exe"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
& $VenvPip install --upgrade pip | Out-Null
& $VenvPip install melee
& $VenvPython --version

# -----------------------------------------------------------------------------
# 7. env.ps1
# -----------------------------------------------------------------------------
Write-Host "[7/7] Writing env.ps1..."
$EnvFile = Join-Path $RepoDir "env.ps1"
@"
# Dot-source this file before running arena.py:
#   . .\env.ps1
#
# Paths for the Smash for Sydney project (libmelee).

# Path to the Slippi Dolphin install directory.
# libmelee expects a dir whose name contains 'netplay' (Ishiiruka build)
# and that contains 'Slippi Dolphin.exe'.
`$env:SLIPPI_PATH = "$InstallDir"

# Path to your Super Smash Bros. Melee ISO.
`$env:SMASH_ISO_PATH = "$IsoPath"
"@ | Set-Content -Path $EnvFile -Encoding UTF8
Write-Host "      wrote $EnvFile"

# -----------------------------------------------------------------------------
# Verify libmelee can find the dolphin exe
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Verifying libmelee can resolve the dolphin executable ==="
$env:SLIPPI_PATH = $InstallDir
$tmpPy = Join-Path $env:TEMP "smash_verify.py"
@"
import os, melee
from melee.console import get_exe_path, _is_mainline
p = os.path.expanduser(os.getenv('SLIPPI_PATH'))
print('SLIPPI_PATH:', p)
print('is_mainline:', _is_mainline(p))
exe = get_exe_path(p)
print('exe:', exe, '| exists:', os.path.isfile(exe))
"@ | Set-Content -Path $tmpPy -Encoding UTF8
& $VenvPython $tmpPy
Remove-Item $tmpPy -Force -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================"
Write-Host "Setup complete!"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Download the Melee ISO and place it at:"
Write-Host "       $IsoPath"
Write-Host "     (if elsewhere, edit SMASH_ISO_PATH in env.ps1)"
Write-Host ""
Write-Host "  2. Run the bots:"
Write-Host "       cd `"$RepoDir`""
Write-Host "       . .\env.ps1"
Write-Host "       .\.venv\Scripts\python.exe arena.py"
Write-Host ""
Write-Host "  Dolphin will boot, pick characters, and start the"
Write-Host "  Masher vs Example fight automatically."
Write-Host "============================================================"