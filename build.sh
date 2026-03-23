#!/bin/bash
# build.sh - Builds the ubuntu-handheld .deb package
# Run from the deb/ directory or the repo root.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEB_ROOT="$SCRIPT_DIR/deb"
OUTPUT="$SCRIPT_DIR/ubuntu-handheld_1.0_amd64.deb"

echo "=== Building ubuntu-handheld package ==="

# Ensure DEBIAN maintainer scripts are executable (dpkg-deb requires this)
chmod 0755 "$DEB_ROOT/DEBIAN/preinst"
chmod 0755 "$DEB_ROOT/DEBIAN/postinst"
chmod 0755 "$DEB_ROOT/DEBIAN/postrm"

# Ensure payload scripts are executable
chmod 0755 "$DEB_ROOT/usr/local/bin/steamos-session"
chmod 0755 "$DEB_ROOT/usr/bin/steamos-session-select"

# Fix ownership -- dpkg-deb --root-owner-group sets all files to root:root
# which is what we want for system files.
dpkg-deb --build --root-owner-group "$DEB_ROOT" "$OUTPUT"

echo ""
echo "=== Build complete ==="
echo "Package: $OUTPUT"
echo ""
echo "To install:"
echo "  sudo apt install -y ./$OUTPUT"
echo ""
echo "To remove (reverts all config changes):"
echo "  sudo apt remove ubuntu-handheld"
echo ""
echo "To purge (also removes HHD and desktop shortcut):"
echo "  sudo apt purge ubuntu-handheld"
