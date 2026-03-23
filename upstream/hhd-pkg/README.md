# HHD Debian Packaging (MOTU Submission)

This directory contains the Debian packaging scaffolding for submitting
`hhd` (Handheld Daemon) to the Ubuntu `universe` repository via MOTU.

## Package structure

```
debian/
├── control          # Source + two binary packages (python3-hhd, hhd)
├── rules            # pybuild-based build rules
├── changelog        # Initial changelog entry
├── copyright        # DEP-5 machine-readable copyright
├── watch            # uscan: tracks PyPI for new upstream releases
├── source/format    # "3.0 (quilt)"
└── tests/
    ├── control      # DEP-8 autopkgtest declarations
    ├── basic-import # Test: python3 -c "import hhd"
    └── cli-help     # Test: hhd --help
```

## How to submit to Ubuntu universe (MOTU process)

### 1. Prerequisites

```bash
sudo apt install devscripts debhelper dh-python python3-all \
                 python3-setuptools pybuild-plugin-pyproject \
                 lintian sbuild ubuntu-dev-tools
```

### 2. Get the upstream source

```bash
cd upstream/hhd-pkg
# Download the tarball from PyPI and rename it for Debian
uscan --download-current-version
# Or manually:
pip3 download --no-deps --no-binary :all: hhd==4.1.8
mv hhd-4.1.8.tar.gz ../hhd_4.1.8.orig.tar.gz
```

### 3. Build the source package

```bash
cd upstream/hhd-pkg
# Build a signed source package (you need a GPG key)
debuild -S -sa
# Or unsigned for testing:
debuild -S -sa -us -uc
```

### 4. Validate with lintian

```bash
lintian --display-info --pedantic ../hhd_4.1.8-1.dsc
```

Fix any `E:` (error) and `W:` (warning) lintian tags before submitting.

### 5. Test the build in a clean environment

```bash
# Set up sbuild if you haven't already
mk-sbuild --arch=amd64 oracular   # or the current Ubuntu release

# Build in the clean chroot
sbuild --dist=oracular ../hhd_4.1.8-1.dsc

# Run autopkgtests
autopkgtest ../hhd_4.1.8-1.dsc -- null
```

### 6. Upload to a PPA for review

```bash
# Create a PPA at https://launchpad.net/~yourname/+activate-ppa
dput ppa:yourname/hhd-staging ../hhd_4.1.8-1_source.changes
```

Share the PPA link when requesting sponsorship.

### 7. Request sponsorship

- File a bug on Launchpad: `ubuntu-bug ubuntu` with tag `needs-packaging`
- Attach the `.dsc` and source package files
- Or post to the `ubuntu-motu` mailing list: ubuntu-motu@lists.ubuntu.com
- Reference: https://wiki.ubuntu.com/MOTU/Contributing

### 8. For packages going to Debian first (recommended)

Submit to Debian via the **Debian Mentors** process:
1. Upload to mentors.debian.net: `dput mentors ../hhd_4.1.8-1_source.changes`
2. Request a sponsor: https://mentors.debian.net/packages/
3. A Debian Developer sponsors the upload → it enters Debian
4. Debian→Ubuntu sync brings it into Ubuntu universe automatically

## Notes

- Update `debian/changelog` for each new upstream release using `dch -v X.Y.Z-1`
- Run `uscan --watch` to check if a new upstream exists
- The `Uploaders:` field in `control` should be your real name/email
- The `debian/watch` file uses `pypi.debian.net` (the Debian PyPI mirror) for
  reliable long-term tracking
