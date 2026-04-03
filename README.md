# t2-upower

UPower fork with T2-specific suspend and keyboard-backlight fixes for Intel Macs with a T2 chip.

## Changes

This tree carries a fix in `src/up-kbd-backlight.c` so keyboard brightness recovers after resume on affected T2 systems.

## Required repositories

- `apple-bce`: `https://github.com/deqrocks/apple-bce`
- `t2-kdb-tb`: `https://github.com/deqrocks/t2-kdb-tb`

## Build

```bash
meson setup build -Dgtk-doc=false
ninja -C build
```

## Deploy 
This is for Fedora. Other distros may use different paths.

Fedora, Debian and Ubuntu install `upowerd` to `/usr/libexec/upowerd`.

Arch and CachyOS install it to `/usr/lib/upower/upowerd`.

Fedora / Debian / Ubuntu:

```bash
sudo install -m 0755 build/src/upowerd /usr/libexec/upowerd
sudo systemctl restart upower
```

Arch / CachyOS:

```bash
sudo install -m 0755 build/src/upowerd /usr/lib/upower/upowerd
sudo systemctl restart upower
```
