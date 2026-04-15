#!/bin/sh

set -eu

usage() {
    cat <<EOF
Usage: $0 [build-dir] [output-dir]

Build a Debian package from an existing Meson build directory.

Environment overrides:
  PACKAGE_NAME    Debian package name (default: t2-upower)
  PACKAGE_VERSION Package version (default: parsed from meson.build)
  MAINTAINER      Control file Maintainer field
  DESCRIPTION     Control file Description field
  DEPENDS         Extra comma-separated package dependencies
  NO_COMPILE      Set to 1 to skip 'meson compile'
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

BUILD_DIR=${1:-build}
OUTPUT_DIR=${2:-"$BUILD_DIR/deb"}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if ! command -v meson >/dev/null 2>&1; then
    echo "error: meson is required" >&2
    exit 1
fi

if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "error: dpkg-deb is required" >&2
    exit 1
fi

if ! command -v dpkg >/dev/null 2>&1; then
    echo "error: dpkg is required" >&2
    exit 1
fi

if [ ! -d "$BUILD_DIR" ] || [ ! -f "$BUILD_DIR/build.ninja" ]; then
    echo "error: '$BUILD_DIR' is not a configured Meson build directory" >&2
    exit 1
fi

PACKAGE_NAME=${PACKAGE_NAME:-t2-upower}
PACKAGE_VERSION=${PACKAGE_VERSION:-$(
    sed -n "s/^[[:space:]]*version:[[:space:]]*'\\([^']*\\)'.*/\\1/p" "$REPO_ROOT/meson.build" | head -n 1
)}

if [ -z "$PACKAGE_VERSION" ]; then
    echo "error: failed to determine package version from meson.build" >&2
    exit 1
fi

ARCH=$(dpkg --print-architecture)
MAINTAINER=${MAINTAINER:-$(git -C "$REPO_ROOT" config user.name 2>/dev/null || true)}
if [ -n "$MAINTAINER" ]; then
    GIT_EMAIL=$(git -C "$REPO_ROOT" config user.email 2>/dev/null || true)
    if [ -n "$GIT_EMAIL" ]; then
        MAINTAINER="$MAINTAINER <$GIT_EMAIL>"
    fi
fi
MAINTAINER=${MAINTAINER:-Unknown Maintainer <unknown@example.com>}
DESCRIPTION=${DESCRIPTION:-UPower fork with T2-specific suspend and keyboard-backlight fixes}

BASE_DEPENDS="libc6, libglib2.0-0, libgudev-1.0-0, libpolkit-gobject-1-0"
if [ -n "${DEPENDS:-}" ]; then
    DEPENDS="$BASE_DEPENDS, $DEPENDS"
else
    DEPENDS="$BASE_DEPENDS"
fi

mkdir -p "$OUTPUT_DIR"

TMPDIR_ROOT=$(mktemp -d)
cleanup() {
    rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT INT TERM

STAGE_DIR="$TMPDIR_ROOT/stage"
PKG_DIR="$TMPDIR_ROOT/pkg"
mkdir -p "$STAGE_DIR" "$PKG_DIR/DEBIAN"

if [ "${NO_COMPILE:-0}" != "1" ]; then
    meson compile -C "$BUILD_DIR"
fi

DESTDIR="$STAGE_DIR" meson install -C "$BUILD_DIR" --no-rebuild

cp -a "$STAGE_DIR/." "$PKG_DIR/"

cat >"$PKG_DIR/DEBIAN/control" <<EOF
Package: $PACKAGE_NAME
Version: $PACKAGE_VERSION
Section: admin
Priority: optional
Architecture: $ARCH
Maintainer: $MAINTAINER
Depends: $DEPENDS
Provides: upower
Conflicts: upower
Replaces: upower
Description: $DESCRIPTION
 T2-focused UPower build packaged from this repository's Meson output.
EOF

cat >"$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    if systemctl is-enabled upower >/dev/null 2>&1 || systemctl is-active upower >/dev/null 2>&1; then
        systemctl restart upower >/dev/null 2>&1 || true
    fi
fi
EOF

cat >"$PKG_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
fi
EOF

chmod 0755 "$PKG_DIR/DEBIAN/postinst" "$PKG_DIR/DEBIAN/postrm"

SIZE_KB=$(du -sk "$PKG_DIR" | awk '{print $1}')
printf 'Installed-Size: %s\n' "$SIZE_KB" >>"$PKG_DIR/DEBIAN/control"

DEB_PATH="$OUTPUT_DIR/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$PKG_DIR" "$DEB_PATH"

printf 'Built %s\n' "$DEB_PATH"
