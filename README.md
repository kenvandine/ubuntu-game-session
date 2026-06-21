# Ubuntu Handheld Setup

A Steam OS-like gaming experience on Ubuntu for handheld gaming PCs (Lenovo Legion Go and similar), delivered as **Ubuntu Game Session**.
Two things live here: a **ready-to-install `.deb` package** for end users, and **Debian packaging scaffolding** for getting `hhd` into Ubuntu universe via MOTU.

---

## 1. Tutorials

### Prerequisites

- A fresh installation of **Ubuntu 26.04** on your target device.

### Installing via the `.deb` packages (recommended)

```bash
bash build.sh   # builds ../ubuntu-game-session_1.2-1_all.deb and ../ubuntu-game-autologin_1.2-1_all.deb
```

**Desktop or laptop** — installs an optional "Ubuntu Game Session" at the GDM login screen:
```bash
sudo apt install ../ubuntu-game-session_1.2-1_all.deb
```

**Handheld gaming PC** (Legion Go, Steam Deck, etc.) — adds GDM autologin, HHD, and boot-into-gaming-mode:
```bash
sudo apt install ../ubuntu-game-autologin_1.2-1_all.deb
```
(`ubuntu-game-autologin` pulls in `ubuntu-game-session` automatically as a dependency.)

Reboot. The system boots directly into the Steam Gamepad UI.

### Installing via the setup script

For development or machines without `apt`:

```bash
sudo scripts/ubuntu-handheld-setup.sh
```

Reboot after the script completes.

### First-time use

After booting into the Gamepad UI:
1. Steam will update itself — let it complete.
2. Press **Legion R** (or your device's quick-access button) to open the HHD overlay for TDP and controller tuning.

---

## 2. How-To Guides

### How to switch to the Ubuntu desktop

From the Steam Gamepad UI:
1. Press the **Steam button** → **Power** → **Switch to Desktop**.
2. The GNOME desktop opens automatically (no login prompt).
3. The native on-screen keyboard is available in **Settings → Accessibility → Typing → Screen Keyboard**.

### How to return to Gaming Mode

Click the **Return to Gaming Mode** shortcut on the GNOME desktop.
The system restarts the display manager and auto-logs you into Ubuntu Game Session.

### How to fully uninstall

```bash
sudo apt remove ubuntu-game-autologin    # reverts GDM config, removes services and HHD symlinks
sudo apt purge ubuntu-game-autologin     # also removes HHD venv, /opt/hhd, desktop shortcut
sudo apt remove ubuntu-game-session      # removes session entry and Steam snap
sudo apt purge ubuntu-game-session       # also removes Valve Steam APT key
```

The `postrm` script restores the original `/etc/gdm3/custom.conf` from a backup taken at install time.

### How to rebuild the `.deb` after making changes

```bash
bash build.sh
```

### How to test in a VM before deploying to hardware

```bash
sudo snap install multipass
scripts/test-in-vm.sh
```

Spins up a fresh Ubuntu 26.04 container and runs the setup script through a suite of edge-case tests.

### How to contribute HHD to Ubuntu universe (MOTU)

See [`upstream/hhd-pkg/README.md`](upstream/hhd-pkg/README.md) for the full step-by-step MOTU submission workflow, including building the source package, running `lintian`, testing with `sbuild`, and requesting a sponsor.

---

## 3. Explanation

### Why native Ubuntu over Bazzite?

Immutable distributions like Bazzite are great appliances but are restrictive for developers who rely on `apt` and standard Linux file hierarchies. This project installs native `gamescope`, bridges PipeWire audio to hardware volume buttons via nested `sxhkd`, and configures GDM auto-login — achieving a console feel while keeping the full Ubuntu host underneath.

### Session switching architecture

| Event | Mechanism |
|---|---|
| Boot | `ubuntu-game-session-autologin-reset.service` sets AccountsService session to `ubuntu-game-session` before GDM starts; GDM auto-logs in |
| Switch to Desktop | Steam calls `/usr/bin/ubuntu-game-session-select` → sets session to `ubuntu` → `loginctl terminate-session` |
| Return to Gaming Mode | Desktop shortcut → `busctl` sets session to `ubuntu-game-session` → `systemctl restart gdm3` (polkit rule, no password) |

### Why pip-in-venv for HHD?

`hhd` is not yet in Ubuntu universe. The `/opt/hhd/venv` approach is the correct pattern per PEP 668 for software not packaged for the distro — the same approach used by Home Assistant and Ansible. The `upstream/hhd-pkg/` scaffolding exists to change this long-term.

### The MOTU packaging path

The `upstream/hhd-pkg/` directory contains a complete Debian source package for `hhd`, split into `python3-hhd` (library) and `hhd` (daemon + udev rules). Once accepted into Debian, the package automatically syncs into Ubuntu universe, making `hhd` a proper `apt` dependency and eliminating the pip-in-venv approach entirely.

---

## 4. Reference

### Project layout

```
.
├── scripts/
│   ├── ubuntu-handheld-setup.sh    # standalone setup script
│   └── test-in-vm.sh               # VM integration test
├── src/                            # static payloads shipped in the .deb
│   ├── usr/bin/ubuntu-game-session-select
│   ├── usr/bin/ubuntu-game-session
│   └── usr/share/wayland-sessions/ubuntu-game-session.desktop
├── debian/                         # Debian package source files
│   ├── control                     # source + two binary package metadata
│   ├── rules                       # debhelper build rules
│   ├── ubuntu-game-session.install # maps src/ contents into ubuntu-game-session
│   ├── ubuntu-game-session.preinst # ensures snapd is running
│   ├── ubuntu-game-session.postinst# installs Steam snap
│   ├── ubuntu-game-session.postrm  # purge cleanup
│   ├── ubuntu-game-autologin.postinst # configures GDM, polkit, HHD, services
│   └── ubuntu-game-autologin.postrm   # full revert on remove/purge
├── build.sh                        # wrapper to run dpkg-buildpackage
└── upstream/
    └── hhd-pkg/
        └── debian/                 # MOTU packaging for upstream hhd
```

### Key system files (installed)

| Path | Package | Purpose |
|---|---|---|
| `/usr/bin/ubuntu-game-session` | ubuntu-game-session | Gamescope + Steam launcher wrapper |
| `/usr/bin/ubuntu-game-session-select` | ubuntu-game-session | Steam "Switch to Desktop" hook |
| `/usr/share/wayland-sessions/ubuntu-game-session.desktop` | ubuntu-game-session | GDM session entry |
| `/etc/systemd/system/ubuntu-game-session-autologin-reset.service` | ubuntu-game-autologin | Resets session to Ubuntu Game Session on every boot |
| `/etc/systemd/system/hhd@.service` | ubuntu-game-autologin | HHD daemon (per-user template) |
| `/etc/polkit-1/rules.d/50-gdm-restart.rules` | ubuntu-game-autologin | Allows GDM restart without password |
| `/opt/hhd/venv/` | ubuntu-game-autologin | Isolated Python venv for HHD |
| `/opt/hhd/hhd-ui.AppImage` | ubuntu-game-autologin | HHD overlay UI |
| `/var/lib/ubuntu-game-autologin/` | ubuntu-game-autologin | State directory (holds GDM config backup) |

### Notable dependencies

| Package | Role |
|---|---|
| `gamescope` | Wayland micro-compositor for the Steam Gamepad UI |
| `steam` (snap) | Official Valve Steam client (installed via snap) |
| `hhd` | Handheld Daemon: TDP, controller remapping, fan curves |
| `sxhkd` | Maps hardware volume keys to PipeWire inside Gamescope |
| `acpi-call-dkms` | Exposes TDP limits via `/proc/acpi/call` |
| `libhidapi-hidraw0` | Low-level HID access for the HHD Python modules |
