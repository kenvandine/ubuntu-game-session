# AGENTS.md

Welcome to the `udeck` project! This file provides context and instructions to help AI coding agents work efficiently on this codebase.

## Dev Environment Tips
- This project builds a Debian package (`.deb`) designed for Ubuntu systems (specifically targeting Resolute Raccoon / Ubuntu 26.04).
- The repository structure is split into three main areas:
  - `src/`: Files to be placed on the root filesystem (e.g., `/usr/bin`, `/etc`).
  - `debian/`: Debian packaging configuration (`control`, `changelog`, `postinst`, `rules`).
  - `scripts/`: Standalone scripts like `ubuntu-handheld-setup.sh` (for manual setup).
- Use `./build.sh` from the repository root to compile the `.deb` package. This requires `dpkg-buildpackage`.

## Testing Instructions
- **Never run destructive installation scripts directly on the host system.**
- Use `scripts/test-in-vm.sh` to spin up an isolated Multipass VM for testing installation flows and simulating the handheld environment.
- Always build the deb using `./build.sh` before running the test VM.

## PR Instructions
- If making changes to the codebase, always ensure `debian/changelog` is updated with the new version and a description of the changes.
- Ensure the `debian/udeck.install` manifest correctly includes any newly added files from `src/`.
- Title format: `[Component] Description of change`
