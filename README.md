# t2-upower

UPower fork with T2-specific suspend and keyboard-backlight fixes for Intel Macs with a T2 chip.
## A PR of this fork was accepted upstream on April 15th, 2026. The repo remains here for the time of transition

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
