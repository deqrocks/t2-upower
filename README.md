# t2-upower

UPower fork with T2-specific suspend and keyboard-backlight fixes for Intel Macs with a T2 chip.

## Changes

This tree carries a fix in `src/up-kbd-backlight.c` so keyboard brightness recovers after resume on affected T2 systems.

## Required repositories

- `apple-bce`: `https://github.com/deqrocks/apple-bce`
- `t2-kdb-tb`: `https://github.com/deqrocks/t2-kbd-tb`

## Pre-requisites

For Arch/ Arch-based distributions:

```bash
sudo pacman -S glib2-devel
```

For Debian/ Debian based distributions:

```bash
sudo apt libglib2.0-dev.
```

The Linux T2 headers are also required, if not installed already.

## Build

```bash
meson setup build -Dgtk-doc=false
ninja -C build
```

## Build a `.deb`

After the Meson build completes on Debian or Ubuntu, create a package with:

```bash
./contrib/build-deb.sh build
```

The resulting `.deb` is written to `build/deb/`.

Useful overrides:

```bash
PACKAGE_NAME=t2-upower PACKAGE_VERSION=1.91.2+t2 ./contrib/build-deb.sh build
```

## Build an `.rpm`

After the Meson build completes on Fedora, create a package with:

```bash
./contrib/build-rpm.sh build
```

The resulting `.rpm` is written to `build/rpm/`.

Useful overrides:

```bash
PACKAGE_NAME=t2-upower PACKAGE_RELEASE=1 ./contrib/build-rpm.sh build
```

## Generate a `PKGBUILD`

For Arch or Arch-based distributions, generate a `PKGBUILD` and source tarball with:

```bash
./contrib/build-arch-linux.sh
```

This writes the packaging files to `packaging/arch/`. Then build the package with:

```bash
cd packaging/arch
makepkg -f
```

Useful overrides:

```bash
PKGNAME=t2-upower PKGREL=1 ./contrib/build-arch-linux.sh
```

## Deploy

This is for Fedora. Other distros may use different paths.

Fedora, Debian and Ubuntu install `upowerd` to `/usr/libexec/upowerd`.

Arch and CachyOS install it to `/usr/lib/upower/upowerd`.

Fedora / Fedora-based / Debian / Debian-based:

```bash
sudo install -m 0755 build/src/upowerd /usr/libexec/upowerd
sudo systemctl restart upower
```

Arch / Arch-based:

```bash
sudo install -m 0755 build/src/upowerd /usr/lib/upowerd
sudo systemctl restart upower
```
