#!/bin/bash
# build.sh - Builds the ubuntu-game-session .deb packages using dpkg-buildpackage
# Run from the repo root.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Building ubuntu-game-session packages ==="

if ! command -v dpkg-buildpackage >/dev/null 2>&1; then
    echo "ERROR: dpkg-buildpackage not found."
    echo "Please install the required build tools first:"
    echo "  sudo apt install -y build-essential debhelper"
    exit 1
fi

cd "$SCRIPT_DIR"

# Ensure debian/rules is executable
chmod +x debian/rules

# Build the packages (unsigned, binary only)
dpkg-buildpackage -us -uc -b

VERSION="$(dpkg-parsechangelog -l debian/changelog -S Version 2>/dev/null || echo 0)"

echo ""
echo "=== Build complete ==="
echo "Packages are located in the parent directory:"
echo "  ../ubuntu-game-session_${VERSION}_all.deb"
echo "  ../ubuntu-game-launcher_${VERSION}_all.deb"
echo "  ../ubuntu-game-handheld_${VERSION}_all.deb"
echo ""
echo "To install session only (desktop/laptop):"
echo "  sudo apt install -y ../ubuntu-game-session_${VERSION}_all.deb"
echo ""
echo "To add gaming enhancements to the GNOME desktop (GameMode, MangoHud,"
echo "Steam (Gamescope) launcher):"
echo "  sudo apt install -y ../ubuntu-game-launcher_${VERSION}_all.deb"
echo ""
echo "To install with handheld autologin (Legion Go, Steam Deck, etc.):"
echo "  sudo apt install -y ../hhd_4.1.10-0_all.deb ../python3-hhd_4.1.10-0_all.deb"
echo "  sudo apt install -y ../ubuntu-game-handheld_${VERSION}_all.deb"
echo ""
echo "To remove:"
echo "  sudo apt remove ubuntu-game-handheld   # reverts GDM config, removes services"
echo "  sudo apt remove ubuntu-game-session    # removes session entry"
echo ""
echo "To purge:"
echo "  sudo apt purge ubuntu-game-handheld    # also removes desktop shortcut"
echo "  sudo apt purge ubuntu-game-session"
