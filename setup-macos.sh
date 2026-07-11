#!/usr/bin/env bash
# =============================================================================
# Smash for Sydney - macOS Setup Script
# =============================================================================
# Sets up everything needed to run the Smash for Sydney bot framework on a
# Sets up everything needed to run the Smash for Sydney bot framework on a
# fresh macOS install (Apple Silicon). Idempotent - safe to re-run.
#
# What this does:
#   1. Installs Homebrew (if missing)
#   2. Installs Python 3.12 via Homebrew
#   3. Installs Rosetta 2 (required - Slippi Dolphin is Intel-only)
#   4. Installs Slippi Dolphin (the Ishiiruka emulator libmelee talks to)
#   5. Creates the netplay/ directory layout libmelee expects
#      (symlinks the app + pre-creates the User/Pipes dir)
#   6. Creates the Melee ISO folder
#   7. Creates a Python virtualenv and installs the `melee` library
#   8. Writes env.sh with SLIPPI_PATH / SMASH_ISO_PATH
#
# After running: download the Melee ISO into ~/Documents/Melee/melee.iso
# then:  source env.sh && .venv/bin/python arena.py
#
# Prereq you must do manually:
#   - Download the Super Smash Bros. Melee ISO and place it at
#     ~/Documents/Melee/melee.iso  (or edit SMASH_ISO_PATH in env.sh)
#     ISO link: https://drive.google.com/file/d/1H9QNNFmVpZLys_kMJq44dpkv7EKBQqHZ/view
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Config (edit these if you want different locations)
# -----------------------------------------------------------------------------
PYTHON_VERSION="3.12"
SLIPPI_APP="/Applications/Slippi Dolphin.app"
NETPLAY_DIR="$HOME/Library/Application Support/com.project-slippi.dolphin/netplay"
USER_DIR="$NETPLAY_DIR/User"
ISO_DIR="$HOME/Documents/Melee"
ISO_PATH="$ISO_DIR/melee.iso"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$REPO_DIR/.venv"

echo "=== Smash for Sydney macOS Setup ==="
echo "Repo:  $REPO_DIR"
echo "Venv:  $VENV_DIR"
echo "Slippi: $SLIPPI_APP"
echo "Netplay: $NETPLAY_DIR"
echo "ISO:   $ISO_PATH"
echo ""

# -----------------------------------------------------------------------------
# 1. Homebrew
# -----------------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    echo "[1/8] Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Homebrew on Apple Silicon installs to /opt/homebrew
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    echo "[1/8] Homebrew already installed. ✓"
fi

# -----------------------------------------------------------------------------
# 2. Python 3.12
# -----------------------------------------------------------------------------
PYTHON_BIN="python$PYTHON_VERSION"
HOMEBREW_PY="/opt/homebrew/bin/$PYTHON_BIN"
if [ ! -x "$HOMEBREW_PY" ]; then
    echo "[2/8] Installing python@$PYTHON_VERSION..."
    brew install "python@$PYTHON_VERSION"
else
    echo "[2/8] python@$PYTHON_VERSION already installed. ✓"
fi
echo "        -> $($HOMEBREW_PY --version)"

# -----------------------------------------------------------------------------
# 3. Rosetta 2  (Slippi Dolphin is Intel-only)
# -----------------------------------------------------------------------------
if /usr/bin/arch -arch x86_64 /usr/bin/true >/dev/null 2>&1; then
    echo "[3/8] Rosetta 2 already installed. ✓"
else
    echo "[3/8] Installing Rosetta 2..."
    echo "       (one-time, hard to remove - required for Intel Slippi Dolphin)"
    softwareupdate --install-rosetta --agree-to-license
fi

# -----------------------------------------------------------------------------
# 4. Slippi Dolphin (cask)
# -----------------------------------------------------------------------------
if [ -d "$SLIPPI_APP" ]; then
    echo "[4/8] Slippi Dolphin already installed. ✓"
else
    echo "[4/8] Installing slippi-dolphin cask..."
    brew install --cask slippi-dolphin
fi

# Clear quarantine so it can launch headlessly via libmelee
if xattr "$SLIPPI_APP" 2>/dev/null | grep -q com.apple.quarantine; then
    xattr -dr com.apple.quarantine "$SLIPPI_APP"
    echo "        cleared quarantine attribute"
fi

# -----------------------------------------------------------------------------
# 5. netplay/ directory + symlink + User/Pipes
# libmelee requires the SLIPPI_PATH dir name to contain 'netplay' and to
# contain 'Slippi Dolphin.app'. On macOS the Dolphin home is fixed at
# .../com.project-slippi.dolphin/netplay/User regardless of where the app lives.
# -----------------------------------------------------------------------------
echo "[5/8] Setting up netplay directory layout..."
mkdir -p "$NETPLAY_DIR"
ln -sfh "$SLIPPI_APP" "$NETPLAY_DIR/Slippi Dolphin.app"
mkdir -p "$USER_DIR/Pipes"
echo "        netplay dir: $NETPLAY_DIR"
echo "        app symlink: -> $SLIPPI_APP"

# -----------------------------------------------------------------------------
# 6. ISO folder
# -----------------------------------------------------------------------------
echo "[6/8] Creating ISO folder: $ISO_DIR"
mkdir -p "$ISO_DIR"
if [ -f "$ISO_PATH" ]; then
    echo "        ISO found: $ISO_PATH  ✓"
else
    echo "        ⚠️  No ISO found yet. Download it and place at:"
    echo "           $ISO_PATH"
    echo "           https://drive.google.com/file/d/1H9QNNFmVpZLys_kMJq44dpkv7EKBQqHZ/view"
fi

# -----------------------------------------------------------------------------
# 7. Virtualenv + melee library
# -----------------------------------------------------------------------------
echo "[7/8] Creating venv and installing melee..."
if [ ! -d "$VENV_DIR" ]; then
    "$HOMEBREW_PY" -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null
"$VENV_DIR/bin/pip" install melee
echo "        $($VENV_DIR/bin/python --version)"

# -----------------------------------------------------------------------------
# 8. env.sh
# -----------------------------------------------------------------------------
echo "[8/8] Writing env.sh..."
cat > "$REPO_DIR/env.sh" <<EOF
# Source this file before running arena.py:
#   source env.sh
#
# Paths for the Smash for Sydney project (libmelee).

# Path to the Slippi Dolphin install directory.
# libmelee expects a dir whose name contains 'netplay' and that contains
# 'Slippi Dolphin.app'. We symlink the Homebrew-cask app into the standard
# com.project-slippi.dolphin/netplay location.
export SLIPPI_PATH="$NETPLAY_DIR"

# Path to your Super Smash Bros. Melee ISO.
export SMASH_ISO_PATH="$ISO_PATH"
EOF
echo "        wrote $REPO_DIR/env.sh"

# -----------------------------------------------------------------------------
# Verify libmelee can find the dolphin exe
# -----------------------------------------------------------------------------
echo ""
echo "=== Verifying libmelee can resolve the dolphin executable ==="
SLIPPI_PATH="$NETPLAY_DIR" "$VENV_DIR/bin/python" - <<'PY' || true
import os, melee
from melee.console import get_exe_path, _is_mainline
p = os.path.expanduser(os.getenv("SLIPPI_PATH"))
print("SLIPPI_PATH:", p)
print("is_mainline:", _is_mainline(p))
exe = get_exe_path(p)
print("exe:", exe, "| exists:", os.path.isfile(exe))
PY

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Download the Melee ISO and place it at:"
echo "       $ISO_PATH"
echo "     (if it's elsewhere, edit SMASH_ISO_PATH in env.sh)"
echo ""
echo "  2. Run the bots:"
echo "       cd \"$REPO_DIR\""
echo "       source env.sh"
echo "       .venv/bin/python arena.py"
echo ""
echo "  Dolphin will boot under Rosetta, pick characters, and start"
echo "  the Masher vs Example fight automatically."
echo "============================================================"