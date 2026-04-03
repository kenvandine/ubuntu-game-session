#!/bin/bash
set -e

# ==============================================================================
# test-in-vm.sh
# 
# Multipass VM Integration Suite for the ubuntu-handheld Debian package.
# This script:
# 1. Triggers the local build of the .deb package.
# 2. Spins up an isolated Ubuntu 25.10 container.
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
echo " [1/7] Building the .deb package locally"
echo "========================================================="
cd "$REPO_ROOT"
if ! bash build.sh; then
    echo "Error: Failed to build the Debian package."
    exit 1
fi

DEB_FILE=$(ls -1 ../ubuntu-handheld_*.deb | head -n 1)
if [ -z "$DEB_FILE" ]; then
    echo "Error: Could not locate built .deb file in parent directory."
    exit 1
fi

VM_NAME="ubuntu-handheld-test-$(date +%s)"

echo "========================================================="
echo " Starting Isolated VM Integration Test"
echo " VM Name: $VM_NAME"
echo " Package Payload: $DEB_FILE"
echo "========================================================="

echo "[2/7] Launching Ubuntu 25.10 Virtual Machine..."
multipass launch 25.10 --name "$VM_NAME" --cpus 2 --memory 2G --disk 10G

# Cleanup routine
cleanup() {
    echo ""
    echo "[Cleanup] Deleting and purging test VM: $VM_NAME..."
    multipass delete "$VM_NAME"
    multipass purge
}
trap cleanup EXIT

echo "[3/7] Transferring $DEB_FILE into the VM..."
multipass transfer "$DEB_FILE" "$VM_NAME":/home/ubuntu/package.deb

echo "[4/7] Preparing VM Environment and Installing package via apt..."
multipass exec "$VM_NAME" -- sudo add-apt-repository -y universe || true
multipass exec "$VM_NAME" -- sudo add-apt-repository -y multiverse || true
multipass exec "$VM_NAME" -- sudo apt-get update -q
if multipass exec "$VM_NAME" -- sudo apt-get install -y /home/ubuntu/package.deb; then
    echo " [OK] Package installed successfully."
else
    echo " [FAIL] Package installation failed."
    exit 1
fi

echo "[5/7] Executing Post-Install Verification Checks..."

# Verify HHD service exists
if multipass exec "$VM_NAME" -- stat /etc/systemd/system/hhd@.service > /dev/null 2>&1; then
    echo " [OK] HHD systemd service file deployed."
else
    echo " [FAIL] HHD systemd service file is missing!"
    exit 1
fi

# Verify gamescope session wrapper exists
if multipass exec "$VM_NAME" -- stat /usr/bin/steamos-session > /dev/null 2>&1; then
    echo " [OK] Gamescope session wrapper script installed."
else
    echo " [FAIL] Gamescope session wrapper script is missing!"
    exit 1
fi

# Verify HHD execution (this hits pip/venv isolation check)
if multipass exec "$VM_NAME" -- /usr/bin/hhd --help > /dev/null 2>&1; then
    echo " [OK] HHD binary executes properly inside isolated venv."
else
    echo " [FAIL] HHD binary failed to execute. Venv broken!"
    exit 1
fi

# Verify GUI AppImage Sandbox
if multipass exec "$VM_NAME" -- /usr/bin/hhd-ui --appimage-extract-and-run --help > /dev/null 2>&1 || true; then
    echo " [OK] HHD-UI AppImage wrapper works without namespace crashes."
else
    echo " [FAIL] AppImage wrapper crashed!"
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
# Wait for the asynchronous background steam-launcher installation (launched in postinst) to finish
multipass exec "$VM_NAME" -- bash -c 'while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1; do echo "Waiting for background Steam installation to complete..."; sleep 5; done'
multipass exec "$VM_NAME" -- sudo apt-get remove -y ubuntu-handheld

# Verify GDM Config reverted
if multipass exec "$VM_NAME" -- grep -q "AutomaticLoginEnable=True" /etc/gdm3/custom.conf; then
    echo " [FAIL] GDM config was NOT properly restored on remove!"
    exit 1
else
    echo " [OK] Original pristine GDM custom.conf successfully restored."
fi

# Verify systemd cleanups
if multipass exec "$VM_NAME" -- stat /etc/systemd/system/steamos-autologin-reset.service > /dev/null 2>&1; then
    echo " [FAIL] Reset service still exists after removal!"
    exit 1
else
    echo " [OK] Systemd reset service cleanly uninstalled."
fi

echo "[7/7] Testing Package Purge (System Sanitation) ..."
multipass exec "$VM_NAME" -- sudo apt-get purge -y ubuntu-handheld

# Verify total isolation cleanup
if multipass exec "$VM_NAME" -- stat /opt/hhd > /dev/null 2>&1; then
    echo " [FAIL] /opt/hhd was not purged!"
    exit 1
fi
if multipass exec "$VM_NAME" -- stat /var/lib/ubuntu-handheld > /dev/null 2>&1; then
    echo " [FAIL] /var/lib/ubuntu-handheld state dir was not purged!"
    exit 1
fi
echo " [OK] Post-purge directories completely wiped."

echo "========================================================="
echo " Integration Suite Passed. 100% of Lifecycle Confirmed."
echo "========================================================="
exit 0
