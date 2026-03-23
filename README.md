# Ubuntu Handheld Setup

A SteamOS-like experience on Ubuntu for handheld gaming PCs (Lenovo Legion Go and similar).
Two things live here: a **ready-to-install `.deb` package** for end users, and **Debian packaging scaffolding** for getting `hhd` into Ubuntu universe via MOTU.

---

## 1. Tutorials

### Installing via the `.deb` package (recommended)

```bash
bash build.sh                                      # builds ubuntu-handheld_1.0_amd64.deb
sudo apt install ./ubuntu-handheld_1.0_amd64.deb   # installs everything
```

Reboot. The system boots directly into the Steam Gamepad UI.

### Installing via the setup script

For development or machines without `apt`:

```bash
sudo ./ubuntu-handheld-setup.sh
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
The system restarts the display manager and auto-logs you into SteamOS.

### How to fully uninstall

```bash
sudo apt remove ubuntu-handheld       # reverts GDM config, removes services
sudo apt purge ubuntu-handheld        # also removes HHD, /opt/hhd, desktop shortcut
```

The `postrm` script restores the original `/etc/gdm3/custom.conf` from a backup taken at install time.

### How to rebuild the `.deb` after making changes

```bash
bash build.sh
```

### How to test in a VM before deploying to hardware

```bash
sudo snap install multipass
./test-in-vm.sh
```

Spins up a fresh Ubuntu 25.10 container and runs the setup script through a suite of edge-case tests.

### How to contribute HHD to Ubuntu universe (MOTU)

See [`upstream/hhd-pkg/README.md`](upstream/hhd-pkg/README.md) for the full step-by-step MOTU submission workflow, including building the source package, running `lintian`, testing with `sbuild`, and requesting a sponsor.

---

## 3. Explanation

### Why native Ubuntu over Bazzite?

Immutable distributions like Bazzite are great appliances but are restrictive for developers who rely on `apt` and standard Linux file hierarchies. This project installs native `gamescope`, bridges PipeWire audio to hardware volume buttons via nested `sxhkd`, and configures GDM auto-login — achieving a console feel while keeping the full Ubuntu host underneath.

### Session switching architecture

| Event | Mechanism |
|---|---|
| Boot | `steamos-autologin-reset.service` sets AccountsService session to `steamos` before GDM starts; GDM auto-logs in |
| Switch to Desktop | Steam calls `/usr/bin/steamos-session-select` → sets session to `ubuntu` → `loginctl terminate-session` |
| Return to Gaming Mode | Desktop shortcut → `busctl` sets session to `steamos` → `systemctl restart gdm3` (polkit rule, no password) |

### Why pip-in-venv for HHD?

`hhd` is not yet in Ubuntu universe. The `/opt/hhd/venv` approach is the correct pattern per PEP 668 for software not packaged for the distro — the same approach used by Home Assistant and Ansible. The `upstream/hhd-pkg/` scaffolding exists to change this long-term.

### The MOTU packaging path

The `upstream/hhd-pkg/` directory contains a complete Debian source package for `hhd`, split into `python3-hhd` (library) and `hhd` (daemon + udev rules). Once accepted into Debian, the package automatically syncs into Ubuntu universe, making `hhd` a proper `apt` dependency and eliminating the pip-in-venv approach entirely.

---

## 4. Reference

### Project layout

```
.
├── ubuntu-handheld-setup.sh        # standalone setup script
├── build.sh                        # builds the .deb
├── test-in-vm.sh                   # VM integration test
├── ubuntu-handheld_1.0_amd64.deb  # built package (gitignored)
├── deb/
│   ├── DEBIAN/
│   │   ├── control                 # package metadata + deps
│   │   ├── preinst                 # adds Valve APT repo + GPG key
│   │   ├── postinst                # configures GDM, polkit, HHD, services
│   │   └── postrm                  # full revert on remove/purge
│   ├── etc/apt/sources.list.d/
│   │   └── steam.list              # Valve Steam APT source
│   └── usr/
│       ├── bin/steamos-session-select
│       ├── local/bin/steamos-session
│       └── share/wayland-sessions/steamos.desktop
└── upstream/
    └── hhd-pkg/
        └── debian/                 # MOTU packaging for Ubuntu universe
```

### Key system files (installed)

| Path | Purpose |
|---|---|
| `/usr/local/bin/steamos-session` | Gamescope + Steam launcher wrapper |
| `/usr/bin/steamos-session-select` | Steam "Switch to Desktop" hook |
| `/usr/share/wayland-sessions/steamos.desktop` | GDM session entry |
| `/etc/systemd/system/steamos-autologin-reset.service` | Resets session to SteamOS on every boot |
| `/etc/systemd/system/hhd@.service` | HHD daemon (per-user template) |
| `/etc/polkit-1/rules.d/50-gdm-restart.rules` | Allows GDM restart without password |
| `/etc/apt/sources.list.d/steam.list` | Valve Steam APT repository |
| `/opt/hhd/venv/` | Isolated Python venv for HHD |
| `/opt/hhd/hhd-ui.AppImage` | HHD overlay UI |
| `/var/lib/ubuntu-handheld/` | State directory (holds GDM config backup) |

### Notable dependencies

| Package | Role |
|---|---|
| `gamescope` | Wayland micro-compositor for the Steam Gamepad UI |
| `steam-launcher` | Official Valve Steam client (from Valve APT repo) |
| `hhd` | Handheld Daemon: TDP, controller remapping, fan curves |
| `sxhkd` | Maps hardware volume keys to PipeWire inside Gamescope |
| `acpi-call-dkms` | Exposes TDP limits via `/proc/acpi/call` |
| `libhidapi-hidraw0` | Low-level HID access for the HHD Python modules |
