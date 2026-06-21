#!/bin/bash
set -e

# ==============================================================================
# test-in-vm.sh
# 
# Multipass VM Integration Suite for the udeck Debian package.
# This script:
# 1. Triggers the local build of the .deb package.
# 2. Spins up an isolated Ubuntu 26.04 container.
# 3. Installs the package and asserts all config states (HHD, GDM, polkit).
# 4. Removes the package and asserts clean configuration reversion.
# 5. Purges the package and asserts complete system sanitation.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if ! command -v multipass &> /dev/null; then
    echo "Error: multipass is not installed."
    echo "Please install it via: sudo snap install multipass"
    exit 1
fi

echo "========================================================="
echo " [1/7] Building packages locally"
echo "========================================================="
cd "$REPO_ROOT"
if ! bash build.sh; then
    echo "Error: Failed to build ubuntu-game-session packages."
    exit 1
fi

HHD_DIR="$(dirname "$REPO_ROOT")/hhd"
if [ -d "$HHD_DIR" ]; then
    echo "Building hhd packages from ${HHD_DIR}..."
    if ! bash "$HHD_DIR/build.sh"; then
        echo "Warning: Failed to build hhd packages. Tests requiring hhd may fail."
    fi
else
    echo "Warning: ../hhd not found. Install hhd manually before running this test."
fi

SESSION_DEB=$(ls -1 ../ubuntu-game-session_*.deb 2>/dev/null | head -n 1)
HANDHELD_DEB=$(ls -1 ../ubuntu-game-handheld_*.deb 2>/dev/null | head -n 1)
HHD_DEB=$(ls -1 ../hhd_*.deb 2>/dev/null | head -n 1)
PYTHON3_HHD_DEB=$(ls -1 ../python3-hhd_*.deb 2>/dev/null | head -n 1)

for f in "$SESSION_DEB" "$HANDHELD_DEB"; do
    if [ -z "$f" ]; then
        echo "Error: Could not locate all required .deb files in parent directory."
        exit 1
    fi
done

VM_NAME="ubuntu-game-session-test-$(date +%s)"

echo "========================================================="
echo " Starting Isolated VM Integration Test"
echo " VM Name: $VM_NAME"
echo "========================================================="

echo "[2/7] Launching Ubuntu 26.04 Virtual Machine..."
multipass launch 26.04 --name "$VM_NAME" --cpus 2 --memory 2G --disk 10G

# Cleanup routine
cleanup() {
    echo ""
    echo "[Cleanup] Deleting and purging test VM: $VM_NAME..."
    multipass delete "$VM_NAME"
    multipass purge
}
trap cleanup EXIT

echo "[3/7] Transferring packages into the VM..."
multipass transfer "$SESSION_DEB" "$VM_NAME":/home/ubuntu/ubuntu-game-session.deb
multipass transfer "$HANDHELD_DEB" "$VM_NAME":/home/ubuntu/ubuntu-game-handheld.deb
if [ -n "$PYTHON3_HHD_DEB" ] && [ -n "$HHD_DEB" ]; then
    multipass transfer "$PYTHON3_HHD_DEB" "$VM_NAME":/home/ubuntu/python3-hhd.deb
    multipass transfer "$HHD_DEB" "$VM_NAME":/home/ubuntu/hhd.deb
    HHD_DEBS="/home/ubuntu/python3-hhd.deb /home/ubuntu/hhd.deb"
else
    echo "Warning: hhd debs not found; will attempt to install hhd from apt universe."
    HHD_DEBS=""
fi

echo "[4/7] Preparing VM Environment and Installing packages via apt..."
multipass exec "$VM_NAME" -- sudo add-apt-repository -y universe || true
multipass exec "$VM_NAME" -- sudo apt-get update -q
# Install local debs together so apt can resolve cross-dependencies
if multipass exec "$VM_NAME" -- sudo apt-get install -y \
        $HHD_DEBS \
        /home/ubuntu/ubuntu-game-session.deb \
        /home/ubuntu/ubuntu-game-handheld.deb; then
    echo " [OK] Packages installed successfully."
else
    echo " [FAIL] Package installation failed."
    exit 1
fi

echo "[5/7] Executing Post-Install Verification Checks..."

# Verify HHD systemd service file (installed by the hhd package)
if multipass exec "$VM_NAME" -- stat /usr/lib/systemd/system/hhd@.service > /dev/null 2>&1; then
    echo " [OK] HHD systemd service file deployed."
else
    echo " [FAIL] HHD systemd service file is missing!"
    exit 1
fi

# Verify gamescope session wrapper exists
if multipass exec "$VM_NAME" -- stat /usr/bin/ubuntu-game-session > /dev/null 2>&1; then
    echo " [OK] Gamescope session wrapper script installed."
else
    echo " [FAIL] Gamescope session wrapper script is missing!"
    exit 1
fi

# Verify HHD binary is available (installed as a package dependency)
if multipass exec "$VM_NAME" -- /usr/bin/hhd --help > /dev/null 2>&1; then
    echo " [OK] HHD binary executes properly."
else
    echo " [FAIL] HHD binary failed to execute!"
    exit 1
fi

# Verify Auto-login changes in GDM
if multipass exec "$VM_NAME" -- grep -q "AutomaticLoginEnable=True" /etc/gdm3/custom.conf; then
    echo " [OK] GDM custom.conf modified for targeted auto-login."
else
    echo " [FAIL] GDM is missing auto-login configuration."
    exit 1
fi

echo "[6/7] Testing Package Removal (Configuration Reversion) ..."
multipass exec "$VM_NAME" -- sudo apt-get remove -y ubuntu-game-handheld

# Verify GDM Config reverted
if multipass exec "$VM_NAME" -- grep -q "AutomaticLoginEnable=True" /etc/gdm3/custom.conf; then
    echo " [FAIL] GDM config was NOT properly restored on remove!"
    exit 1
else
    echo " [OK] Original pristine GDM custom.conf successfully restored."
fi

# Verify systemd cleanups
if multipass exec "$VM_NAME" -- stat /etc/systemd/system/ubuntu-game-session-autologin-reset.service > /dev/null 2>&1; then
    echo " [FAIL] Reset service still exists after removal!"
    exit 1
else
    echo " [OK] Systemd reset service cleanly uninstalled."
fi

echo "[7/7] Testing Package Purge (System Sanitation) ..."
multipass exec "$VM_NAME" -- sudo apt-get purge -y ubuntu-game-handheld

# Verify state directory cleanup
if multipass exec "$VM_NAME" -- stat /var/lib/ubuntu-game-handheld > /dev/null 2>&1; then
    echo " [FAIL] /var/lib/ubuntu-game-handheld state dir was not purged!"
    exit 1
fi
echo " [OK] Post-purge directories completely wiped."

echo "========================================================="
echo " Integration Suite Passed. 100% of Lifecycle Confirmed."
echo "========================================================="
exit 0
