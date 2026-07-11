#!/usr/bin/env bash
# =============================================================================
# Smash for Sydney - Linux Setup Script
# =============================================================================
# Sets up everything to run the Smash for Sydney bot framework on a fresh
# Linux install (x86_64). Idempotent - safe to re-run.
#
# What this does:
#   1. Verifies python3 / pip
#   2. Downloads the Slippi Dolphin Linux build (Ishiiruka) from GitHub
#   3. Extracts the AppImage + Sys files into a 'netplay/' dir
#      (libmelee requires the SLIPPI_PATH to contain 'netplay')
#   4. Makes the AppImage executable
#   5. Creates the Dolphin home (~/.config/SlippiOnline) + Pipes dir
#      (libmelee's named-pipe controllers live here on Linux)
#   6. Creates the Melee ISO folder
#   7. Creates a Python virtualenv and installs the `melee` library
#   8. Writes env.sh with SLIPPI_PATH / SMASH_ISO_PATH
#
# Requirements (NOT installed by this script):
#   - FUSE must be available (AppImages need it). Install via your package
#     manager, e.g.:  sudo apt install libfuse2     (Debian/Ubuntu)
#                 or: sudo dnf install fuse          (Fedora)
#   - A C++ runtime is sometimes needed (libmelee note):
#                 sudo apt install build-essential   (Debian/Ubuntu)
#
# After running: download the Melee ISO into ~/Documents/Melee/melee.iso
# then:  source env.sh && .venv/bin/python arena.py
#
# Manual step: download the Super Smash Bros. Melee ISO and place at
#   ~/Documents/Melee/melee.iso   (or edit SMASH_ISO_PATH in env.sh)
#   ISO link: https://drive.google.com/file/d/1H9QNNFmVpZLys_kMJq44dpkv7EKBQqHZ/view
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Config (edit these if you want different locations)
# -----------------------------------------------------------------------------
SLIPPI_VERSION="3.6.4"
SLIPPI_ZIP_URL="https://github.com/project-slippi/Ishiiruka/releases/download/v${SLIPPI_VERSION}/FM-Slippi-${SLIPPI_VERSION}-Linux.zip"
INSTALL_DIR="$HOME/.local/share/slippi-dolphin/netplay"   # must contain 'netplay'
DOLPHIN_HOME="$HOME/.config/SlippiOnline"                  # libmelee Linux non-mainline home
ISO_DIR="$HOME/Documents/Melee"
ISO_PATH="$ISO_DIR/melee.iso"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$REPO_DIR/.venv"

echo "=== Smash for Sydney Linux Setup ==="
echo "Repo:        $REPO_DIR"
echo "Venv:        $VENV_DIR"
echo "Slippi dir:  $INSTALL_DIR"
echo "Dolphin home:$DOLPHIN_HOME"
echo "ISO:         $ISO_PATH"
echo ""

# -----------------------------------------------------------------------------
# 1. Python 3 + pip
# -----------------------------------------------------------------------------
echo "[1/8] Checking Python..."
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 not found. Install via your package manager:"
    echo "  sudo apt install python3 python3-venv python3-pip   (Debian/Ubuntu)"
    echo "  sudo dnf install python3 python3-pip                 (Fedora)"
    exit 1
fi
echo "      $(python3 --version)  ✓"

for dep in unzip; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "ERROR: '$dep' not found. Install via your package manager:"
        echo "  sudo apt install $dep   (Debian/Ubuntu)"
        echo "  sudo dnf install $dep     (Fedora)"
        exit 1
    fi
done

# -----------------------------------------------------------------------------
# 2. Download Slippi Dolphin (Linux zip)
# -----------------------------------------------------------------------------
APPIMAGE="$INSTALL_DIR/Slippi_Online-x86_64.AppImage"   # name libmelee expects
if [ -f "$APPIMAGE" ]; then
    echo "[2/8] Slippi Dolphin already extracted. ✓"
else
    echo "[2/8] Downloading Slippi Dolphin v${SLIPPI_VERSION} (Linux)..."
    TMP_ZIP="$(mktemp -d)/slippi-linux.zip"
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo "ERROR: need curl or wget to download. Install one:"
        echo "  sudo apt install curl   (Debian/Ubuntu)"
        exit 1
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$TMP_ZIP" "$SLIPPI_ZIP_URL"
    else
        wget -q -O "$TMP_ZIP" "$SLIPPI_ZIP_URL"
    fi
    mkdir -p "$INSTALL_DIR"
    unzip -q -o "$TMP_ZIP" -d "$INSTALL_DIR"
    rm -f "$TMP_ZIP"
    echo "      extracted -> $INSTALL_DIR"
fi

# -----------------------------------------------------------------------------
# 3. Verify the AppImage exists (libmelee looks for this exact name)
# -----------------------------------------------------------------------------
echo "[3/8] Verifying AppImage..."
if [ ! -f "$APPIMAGE" ]; then
    echo "ERROR: expected AppImage not found at $APPIMAGE"
    echo "       Found these files in $INSTALL_DIR:"
    ls -la "$INSTALL_DIR" | head
    exit 1
fi
echo "      $APPIMAGE  ✓"

# -----------------------------------------------------------------------------
# 4. Make AppImage executable
# -----------------------------------------------------------------------------
echo "[4/8] Making AppImage executable..."
chmod +x "$APPIMAGE"
if [ ! -x "$APPIMAGE" ]; then
    echo "ERROR: could not make AppImage executable"
    exit 1
fi
echo "      executable  ✓"

# -----------------------------------------------------------------------------
# 5. Dolphin home + Pipes (libmelee named-pipe controllers on Linux)
# -----------------------------------------------------------------------------
echo "[5/8] Setting up Dolphin home ($DOLPHIN_HOME) + Pipes..."
mkdir -p "$DOLPHIN_HOME/Pipes"
echo "      ready  ✓"

# -----------------------------------------------------------------------------
# 6. ISO folder
# -----------------------------------------------------------------------------
echo "[6/8] Creating ISO folder: $ISO_DIR"
mkdir -p "$ISO_DIR"
if [ -f "$ISO_PATH" ]; then
    echo "      ISO found: $ISO_PATH  ✓"
else
    echo "      ⚠️  No ISO yet. Download and place at:"
    echo "           $ISO_PATH"
    echo "           https://drive.google.com/file/d/1H9QNNFmVpZLys_kMJq44dpkv7EKBQqHZ/view"
fi

# -----------------------------------------------------------------------------
# 7. Virtualenv + melee library
# -----------------------------------------------------------------------------
echo "[7/8] Creating venv and installing melee..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null
"$VENV_DIR/bin/pip" install melee
echo "      $($VENV_DIR/bin/python --version)"

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
# libmelee expects a dir whose name contains 'netplay' (Ishiiruka build)
# and that contains 'Slippi_Online-x86_64.AppImage'.
export SLIPPI_PATH="$INSTALL_DIR"

# Path to your Super Smash Bros. Melee ISO.
export SMASH_ISO_PATH="$ISO_PATH"
EOF
echo "      wrote $REPO_DIR/env.sh"

# -----------------------------------------------------------------------------
# Verify libmelee can find the dolphin exe
# -----------------------------------------------------------------------------
echo ""
echo "=== Verifying libmelee can resolve the dolphin executable ==="
SLIPPI_PATH="$INSTALL_DIR" "$VENV_DIR/bin/python" - <<'PY' || true
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
echo "Requirements reminder (if the AppImage won't launch):"
echo "  - FUSE:  sudo apt install libfuse2     (Debian/Ubuntu)"
echo "           sudo dnf install fuse          (Fedora)"
echo "  - C++:   sudo apt install build-essential  (optional)"
echo ""
echo "Next steps:"
echo "  1. Download the Melee ISO and place it at:"
echo "       $ISO_PATH"
echo "     (if elsewhere, edit SMASH_ISO_PATH in env.sh)"
echo ""
echo "  2. Run the bots:"
echo "       cd \"$REPO_DIR\""
echo "       source env.sh"
echo "       .venv/bin/python arena.py"
echo ""
echo "  Dolphin will boot, pick characters, and start the"
echo "  Masher vs Example fight automatically."
echo "============================================================"