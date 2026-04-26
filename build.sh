#!/bin/bash
# build.sh - Builds the ubuntu-handheld .deb package using dpkg-buildpackage
# Run from the repo root.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Building ubuntu-handheld package ==="

if ! command -v dpkg-buildpackage >/dev/null 2>&1; then
    echo "ERROR: dpkg-buildpackage not found."
    echo "Please install the required build tools first:"
    echo "  sudo apt install -y build-essential debhelper"
    exit 1
fi

cd "$SCRIPT_DIR"

# Ensure debian/rules is executable
chmod +x debian/rules

# Build the package (unsigned, binary only)
dpkg-buildpackage -us -uc -b

echo ""
echo "=== Build complete ==="
echo "Package is located in the parent directory: ../ubuntu-handheld_1.1-1_all.deb"
echo ""
echo "To install:"
echo "  sudo apt install -y ../ubuntu-handheld_1.1-1_all.deb"
echo ""
echo "To remove (reverts all config changes):"
echo "  sudo apt remove ubuntu-handheld"
echo ""
echo "To purge (also removes HHD and desktop shortcut):"
echo "  sudo apt purge ubuntu-handheld"
