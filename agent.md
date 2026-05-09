# Agent Log

## Update Unified Memory Kernel Flags
- Replaced the deprecated `amdgpu.gttsize` GRUB kernel parameter with the modern `ttm.pages_limit` parameter.
- Configured the allocation limit to cover the entire 32GB of system memory.
- The new limit is set to `8388608` pages (each page is 4 KiB, equating to 32GB).
- Updated the configuration in:
  - `src/etc/default/grub.d/10-udeck.cfg` (Drop-in file for the Debian package)
  - `scripts/ubuntu-handheld-setup.sh` (Standalone setup script)
- Re-built the `.deb` package to package the new configurations.
