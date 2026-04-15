#!/bin/sh

set -eu

usage() {
    cat <<EOF
Usage: $0 [-i|--install] [output-dir]

Build an Arch package in a staged repo copy.

Environment overrides:
  PKGNAME        Arch package name (default: t2-upower)
  PKGVER         Package version (default: parsed from meson.build)
  PKGREL         Package release (default: 1)
  PKGDESC        PKGBUILD pkgdesc field
  URL            PKGBUILD url field
  LICENSE        PKGBUILD license field (default: GPL2)
  ARCHES         PKGBUILD arch array contents (default: x86_64)
  DEPENDS        PKGBUILD depends array contents
  MAKEDEPENDS    PKGBUILD makedepends array contents
EOF
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$SCRIPT_DIR

INSTALL=0
OUTPUT_DIR=

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -i|--install)
            INSTALL=1
            ;;
        -*)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [ -n "$OUTPUT_DIR" ]; then
                echo "error: too many arguments" >&2
                usage >&2
                exit 1
            fi
            OUTPUT_DIR=$1
            ;;
    esac
    shift
done

OUTPUT_DIR=${OUTPUT_DIR:-"$REPO_ROOT/pkg/arch-linux"}

if ! command -v sha256sum >/dev/null 2>&1; then
    echo "error: sha256sum is required" >&2
    exit 1
fi

PKGNAME=${PKGNAME:-t2-upower}
PKGVER=${PKGVER:-$(
    sed -n "s/^[[:space:]]*version:[[:space:]]*'\\([^']*\\)'.*/\\1/p" "$REPO_ROOT/meson.build" | head -n 1
)}
PKGREL=${PKGREL:-1}
PKGDESC=${PKGDESC:-UPower fork with T2-specific suspend and keyboard-backlight fixes}
URL=${URL:-https://github.com/deqrocks/t2-upower}
LICENSE=${LICENSE:-GPL2}
ARCHES=${ARCHES:-x86_64}
DEPENDS=${DEPENDS:-glib2 libgudev polkit}
MAKEDEPENDS=${MAKEDEPENDS:-git meson gcc pkgconf glib2 libgudev polkit}

if [ -z "$PKGVER" ]; then
    echo "error: failed to determine package version from meson.build" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

TARBALL_NAME="${PKGNAME}-${PKGVER}.tar.gz"
TARBALL_PATH="$OUTPUT_DIR/$TARBALL_NAME"
STAGE_REPO_DIR="$OUTPUT_DIR/${PKGNAME}-${PKGVER}"
PKGBUILD_PATH="$OUTPUT_DIR/PKGBUILD"

rm -rf "$STAGE_REPO_DIR" "$OUTPUT_DIR/src" "$OUTPUT_DIR/pkg"
find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.pkg.tar.*' -delete
find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.pkg.zst' -delete
find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.tar.gz' -delete
rm -f "$PKGBUILD_PATH"

mkdir -p "$STAGE_REPO_DIR"

tar \
    --exclude="$OUTPUT_DIR" \
    --exclude='./build' \
    --exclude='./pkg' \
    --exclude='./.git' \
    -cf - -C "$REPO_ROOT" . | tar -xf - -C "$STAGE_REPO_DIR"

rm -f \
    "$STAGE_REPO_DIR/README.md" \
    "$STAGE_REPO_DIR/build-arch-linux.sh" \
    "$STAGE_REPO_DIR/build-deb.sh" \
    "$STAGE_REPO_DIR/build-rpm.sh"

tar -czf "$TARBALL_PATH" -C "$OUTPUT_DIR" "${PKGNAME}-${PKGVER}"
SHA256=$(sha256sum "$TARBALL_PATH" | awk '{print $1}')

cat >"$PKGBUILD_PATH" <<EOF
pkgname=$PKGNAME
pkgver=$PKGVER
pkgrel=$PKGREL
pkgdesc='$PKGDESC'
arch=($ARCHES)
url='$URL'
license=($LICENSE)
depends=($DEPENDS)
makedepends=($MAKEDEPENDS)
source=($TARBALL_NAME)
sha256sums=($SHA256)

build() {
  cd "\$srcdir/$PKGNAME-$PKGVER"
  meson setup build -Dgtk-doc=false -Dman=false
  meson compile -C build
}

package() {
  cd "\$srcdir/$PKGNAME-$PKGVER"
  DESTDIR="\$pkgdir" meson install -C build --no-rebuild
}
EOF

printf 'Staged repo copy in %s\n' "$STAGE_REPO_DIR"
printf 'Generated %s\n' "$PKGBUILD_PATH"
printf 'Generated %s\n' "$TARBALL_PATH"
cd "$OUTPUT_DIR"
if [ "$INSTALL" -eq 1 ]; then
    makepkg -si
else
    makepkg -s
fi
