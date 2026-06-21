# Ubuntu Handheld Setup

A Steam OS-like gaming experience on Ubuntu for handheld gaming PCs (Lenovo Legion Go and similar), delivered as **Ubuntu Game Session**.
Two things live here: a **ready-to-install `.deb` package** for end users, and **Debian packaging scaffolding** for getting `hhd` into Ubuntu universe via MOTU.

---

## 1. Tutorials

### Prerequisites

- A fresh installation of **Ubuntu 26.04** on your target device.

### Installing via the `.deb` packages (recommended)

```bash
bash build.sh   # builds ../ubuntu-game-session_1.3-1_all.deb and ../ubuntu-game-handheld_1.3-1_all.deb
```

**Desktop or laptop** — installs an optional "Ubuntu Game Session" at the GDM login screen:
```bash
sudo apt install ../ubuntu-game-session_1.2-1_all.deb
```

**Handheld gaming PC** (Legion Go, Steam Deck, etc.) — adds GDM autologin, HHD, and boot-into-gaming-mode:
```bash
# Build hhd packages first (from the sibling ../hhd repo)
cd ../hhd && dpkg-buildpackage -us -uc -b && cd -
sudo apt install -y ../python3-hhd_4.1.10-1_all.deb ../hhd_4.1.10-1_all.deb
sudo apt install -y ../ubuntu-game-handheld_1.3-1_all.deb
```
(`ubuntu-game-handheld` pulls in `ubuntu-game-session` and `hhd` automatically as dependencies.)

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
sudo apt remove ubuntu-game-handheld    # reverts GDM config, removes services
sudo apt purge ubuntu-game-handheld     # also removes desktop shortcut and state
sudo apt remove ubuntu-game-session     # removes session entry
sudo apt remove hhd python3-hhd        # removes Handheld Daemon
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

### Why a separate hhd package?

`hhd` is packaged as a proper Debian source package in the sibling `../hhd` repository. Once accepted into Ubuntu universe, it will be available via `apt` as a standard dependency. Until then, build it locally from `../hhd` and install it before `ubuntu-game-handheld`. The `upstream/hhd-pkg/` directory contains the original MOTU scaffolding reference.

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
│   ├── ubuntu-game-handheld.postinst # configures GDM, polkit, HHD service-enable
│   └── ubuntu-game-handheld.postrm   # full revert on remove/purge
├── build.sh                        # wrapper to run dpkg-buildpackage
└── upstream/
    └── hhd-pkg/                    # original MOTU packaging scaffold (reference)
```

### Key system files (installed)

| Path | Package | Purpose |
|---|---|---|
| `/usr/bin/ubuntu-game-session` | ubuntu-game-session | Gamescope + Steam launcher wrapper |
| `/usr/bin/ubuntu-game-session-select` | ubuntu-game-session | Steam "Switch to Desktop" hook |
| `/usr/share/wayland-sessions/ubuntu-game-session.desktop` | ubuntu-game-session | GDM session entry |
| `/etc/systemd/system/ubuntu-game-session-autologin-reset.service` | ubuntu-game-handheld | Resets session to Ubuntu Game Session on every boot |
| `/etc/systemd/system/hhd@.service` | hhd | HHD daemon (per-user template) |
| `/etc/polkit-1/rules.d/50-gdm-restart.rules` | ubuntu-game-handheld | Allows GDM restart without password |
| `/usr/lib/udev/rules.d/83-hhd*.rules` | hhd | HID device access rules for controllers |
| `/var/lib/ubuntu-game-handheld/` | ubuntu-game-handheld | State directory (holds GDM config backup) |

### Notable dependencies

| Package | Role |
|---|---|
| `gamescope` | Wayland micro-compositor for the Steam Gamepad UI |
| `steam` (snap) | Official Valve Steam client (installed via snap) |
| `hhd` | Handheld Daemon: TDP, controller remapping, fan curves (separate package) |
| `sxhkd` | Maps hardware volume keys to PipeWire inside Gamescope |
| `acpi-call-dkms` | Exposes TDP limits via `/proc/acpi/call` |
| `libhidapi-hidraw0` | Low-level HID access for HHD (dependency of hhd package) |
