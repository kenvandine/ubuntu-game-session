#!/bin/bash
set -e

# ==============================================================================
# ubuntu-handheld-setup.sh
# 
# A script to configure an Ubuntu system to act similarly to Bazzite for handheld
# devices (like Lenovo Legion Go). It installs Gamescope (Steam UI session),
# Handheld Daemon (HHD) for TDP and controller management, and the HHD overlay.
# It explicitly avoids 'pipx' by utilizing a local Python virtual environment.
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)."
  exit 1
fi

# Identify the original user before sudo elevation
TARGET_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "")}
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    TARGET_USER=$(id -un 1000 2>/dev/null)
fi
if [ -z "$TARGET_USER" ]; then
    echo "ERROR: Could not securely verify user context. Halting."
    exit 1
fi

echo "=========================================="
echo " Starting Ubuntu Handheld Setup"
echo "=========================================="

echo "[1/4] Installing system dependencies via APT..."
apt-get update
apt-get install -y software-properties-common

# Enable universe repository (needed for gamescope)
add-apt-repository -y universe
apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    git \
    python3-venv \
    python3-dev \
    python3-pip \
    build-essential \
    gir1.2-gtk-3.0 \
    gamescope \
    udev \
    systemd \
    libfuse2t64 \
    libhidapi-hidraw0 \
    acpi-call-dkms \
    sxhkd \
    snapd

echo "[1.5/4] Installing Steam via snap..."
if ! snap list steam >/dev/null 2>&1; then
    snap install steam
else
    echo "Steam snap already installed."
fi

echo "[2/4] Setting up Gamescope Steam Session..."
# Create the launcher script
cat << 'EOF' > /usr/bin/ubuntu-game-session
#!/bin/bash
# A basic gamescope session wrapper

# Connect directly to the host's systemd user D-Bus so Steam can communicate with PipeWire/PulseAudio.
# Spawning a new dbus-launch isolates Steam from the audio pipeline!
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# Set environmental variables often needed for Steam UI under gamescope
# Ensure popular steam installation paths (like snap) are available
export PATH="$PATH:/snap/bin:/usr/games:/usr/local/games"
export XDG_SESSION_DESKTOP=ubuntu-game-session
export XDG_CURRENT_DESKTOP=ubuntu-game-session
# Additional environment variables to prevent Wayland-sandbox crashes (especially for snap)
export GDK_BACKEND=x11
export SDL_VIDEODRIVER=x11

# Launch gamescope passing the steam gamepadui
# Assuming 1280x800 for devices like the Steam Deck / Legion Go default scale.
# We pipe the output to a persistent log file so we can diagnose crashes after a reboot.

# The -steamos3 flags cause the initial steam bootstrap to query Valve's OS update servers, 
# Map hardware volume keys directly to PipeWire via sxhkd running internally to Gamescope
mkdir -p "$HOME/.config/sxhkd"
cat << 'KEYBINDINGS' > "$HOME/.config/sxhkd/sxhkdrc"
XF86AudioRaiseVolume
    wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
XF86AudioLowerVolume
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
XF86AudioMute
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
KEYBINDINGS

    # Only activate strict Steam Deck UI flags if steam is fully logged in.
    # Otherwise the "Out of Box Experience" (OOBE) network updater fails.
    STEAM_FLAGS="-gamepadui"
    if [ -f "$HOME/.steam/steam/config/loginusers.vdf" ] || [ -f "$HOME/.local/share/Steam/config/loginusers.vdf" ]; then
        STEAM_FLAGS="-gamepadui -steamos3 -steampal -steamdeck"
    fi

    exec gamescope -e -f -- bash -c "sxhkd -c \"\$HOME/.config/sxhkd/sxhkdrc\" & steam $STEAM_FLAGS" >> "$HOME/ubuntu-game-session.log" 2>&1
EOF
chmod +x /usr/bin/ubuntu-game-session

# Create the wayland session file for GDM
mkdir -p /usr/share/wayland-sessions
cat << 'EOF' > /usr/share/wayland-sessions/ubuntu-game-session.desktop
[Desktop Entry]
Name=Ubuntu Game Session
Comment=Steam Gamepad UI via Gamescope (a Steam OS-like gaming experience)
Exec=/usr/bin/ubuntu-game-session
Type=Application
DesktopNames=ubuntu-game-session
EOF

# Provide ubuntu-game-session-select so "Switch to Desktop" works in the Power Menu
cat << 'EOF' > /usr/bin/ubuntu-game-session-select
#!/bin/bash
# Called by Steam when user clicks "Switch to Desktop".
# Sets AccountsService session to ubuntu, then terminates the Gamescope session.
# GDM auto-login will log back in to the ubuntu desktop.
busctl call org.freedesktop.Accounts "/org/freedesktop/Accounts/User$(id -u)" \
    org.freedesktop.Accounts.User SetXSession s "ubuntu"
busctl call org.freedesktop.Accounts "/org/freedesktop/Accounts/User$(id -u)" \
    org.freedesktop.Accounts.User SetSession s "ubuntu"
pkill gamescope
EOF
chmod +x /usr/bin/ubuntu-game-session-select

# Grant NOPASSWD for GDM restarts (used by "Return to Gaming Mode" desktop shortcut)
# Use printf to avoid any leading whitespace that would break visudo syntax checking.
printf '%s ALL=(ALL) NOPASSWD: /bin/systemctl restart gdm3, /bin/systemctl restart gdm\n' "$TARGET_USER" \
    > /etc/sudoers.d/ubuntu-game-session-switch
chmod 0440 /etc/sudoers.d/ubuntu-game-session-switch

# Write GDM config with tee so AutomaticLogin is always set correctly.
# Using sed against the default file is unreliable -- the keys are commented out
# and the regex never matches, leaving AutomaticLogin blank.
tee /etc/gdm3/custom.conf > /dev/null << GDMEOF
# GDM configuration storage
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=$TARGET_USER
TimedLoginEnable=True
TimedLogin=$TARGET_USER
TimedLoginDelay=3

[security]

[xdmcp]

[chooser]

[debug]
GDMEOF

# Resolve the user UID NOW (while TARGET_USER is set) before writing any heredoc
# that runs as root -- id -u inside a systemd ExecStart would return 0 (root), not the user.
USER_UID=$(id -u "$TARGET_USER")

# On every boot, reset the AccountsService session pointer back to ubuntu-game-session
# so that GDM auto-login always boots into Ubuntu Game Session after a reboot.
cat > /etc/systemd/system/ubuntu-game-session-autologin-reset.service << SVCEOF
[Unit]
Description=Reset Default Session to Ubuntu Game Session on Boot
After=accounts-daemon.service
Before=gdm.service gdm3.service display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/bin/busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User${USER_UID} org.freedesktop.Accounts.User SetXSession s ubuntu-game-session
ExecStart=/usr/bin/busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User${USER_UID} org.freedesktop.Accounts.User SetSession s ubuntu-game-session

[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
systemctl enable ubuntu-game-session-autologin-reset.service

# Also set the session right now so the very first reboot works immediately
busctl call org.freedesktop.Accounts "/org/freedesktop/Accounts/User${USER_UID}" \
    org.freedesktop.Accounts.User SetXSession s ubuntu-game-session
busctl call org.freedesktop.Accounts "/org/freedesktop/Accounts/User${USER_UID}" \
    org.freedesktop.Accounts.User SetSession s ubuntu-game-session

# Allow the user to restart gdm3 without a password via polkit.
# This powers the "Return to Gaming Mode" shortcut without needing sudoers.
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/50-gdm-restart.rules << POLKITEOF
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        (action.lookup("unit") == "gdm3.service" || action.lookup("unit") == "gdm.service") &&
        action.lookup("verb") == "restart" &&
        subject.user == "$TARGET_USER") {
        return polkit.Result.YES;
    }
});
POLKITEOF

# Desktop shortcut to return to Gaming Mode from the GNOME desktop
USER_HOME=$(eval echo ~"$TARGET_USER")
mkdir -p "$USER_HOME/Desktop"
cat > "$USER_HOME/Desktop/Return to Gaming Mode.desktop" << DESKEOF
[Desktop Entry]
Name=Return to Gaming Mode
Comment=Switch back to Ubuntu Game Session
Exec=bash -c 'MY_UID=$(id -u); busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User${MY_UID} org.freedesktop.Accounts.User SetXSession s ubuntu-game-session && busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User${MY_UID} org.freedesktop.Accounts.User SetSession s ubuntu-game-session && sleep 1 && systemctl restart gdm3 2>/dev/null || systemctl restart gdm'
Icon=steam
Type=Application
Terminal=false
DESKEOF
chmod +x "$USER_HOME/Desktop/Return to Gaming Mode.desktop"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/Desktop/Return to Gaming Mode.desktop"
# Mark the shortcut as trusted so GNOME allows launching it from the Desktop
su - "$TARGET_USER" -c \
    "gio set \"$USER_HOME/Desktop/Return to Gaming Mode.desktop\" metadata::trusted true" \
    2>/dev/null || true

# Enable GNOME's native on-screen keyboard (Accessibility → Typing → Screen Keyboard)
# This uses the built-in keyboard rather than a third-party app.
su - "$TARGET_USER" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${USER_UID}/bus \
    gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true" 2>/dev/null || true

echo "[3/4] Installing Handheld Daemon (HHD)..."
# Install hhd and its Python dependencies from apt (Ubuntu universe).
# If hhd is not yet in universe, install from pip as a fallback.
if apt-get install -y hhd 2>/dev/null; then
    echo "hhd installed via apt."
else
    echo "hhd not found in apt repositories; installing via pip..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        python3-evdev python3-yaml python3-rich python3-xlib \
        python3-serial python3-pyroute2 python3-gi python3-dbus \
        python3-setuptools libhidapi-hidraw0
    pip3 install --break-system-packages hhd
fi

echo "[4/4] Configuring Udev Rules and Systemd Services for HHD..."
# Add user to required groups for HID device access
if [ -n "$TARGET_USER" ]; then
    echo "Enabling hhd service for user: $TARGET_USER"
    usermod -aG input,video "$TARGET_USER" || true
    systemctl daemon-reload
    systemctl enable hhd@$TARGET_USER.service
    systemctl restart hhd@$TARGET_USER.service || \
        echo "Warning: HHD could not start (normal if no handheld device is detected or if running in VM)"
else
    echo "Could not detect standard user. To enable HHD on boot, run: sudo systemctl enable hhd@<your_username>"
fi

echo "[5/5] Applying Optimized Kernel Flags for Unified Memory..."
mkdir -p /etc/default/grub.d
cat << 'GRUBEOF' > /etc/default/grub.d/10-udeck.cfg
# Optimized kernel flags for unified memory / APUs
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT ttm.pages_limit=8388608"
GRUBEOF
update-grub || true

echo "=========================================="
echo " Setup Complete! "
echo "=========================================="
echo "What's Next:"
echo "1. Reboot or log out."
echo "2. From the GDM login screen, click the gear icon in the bottom right corner"
echo "   and select 'Ubuntu Game Session' instead of 'Ubuntu' or 'GNOME'."
echo "3. The system will start into the Steam Deck Gamepad UI."
echo "4. Press the quick access button (e.g., Legion R) in-game to launch the hhd-overlay"
echo "   for TDP control and controller tuning."
echo ""
