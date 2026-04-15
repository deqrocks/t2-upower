#!/bin/sh

set -eu

usage() {
    cat <<EOF
Usage: $0 [-i|--install] [output-dir]

Build a Debian package in a staged repo copy.

Environment overrides:
  PACKAGE_NAME    Debian package name (default: t2-upower)
  PACKAGE_VERSION Package version (default: parsed from meson.build)
  MAINTAINER      Control file Maintainer field
  DESCRIPTION     Control file Description field
  DEPENDS         Extra comma-separated package dependencies
  BUILD_DEPENDS   Space-separated apt packages to install before building
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

OUTPUT_DIR=${OUTPUT_DIR:-"$REPO_ROOT/pkg/debian"}

if ! command -v apt-get >/dev/null 2>&1; then
    echo "error: apt-get is required" >&2
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

BUILD_DEPENDS=${BUILD_DEPENDS:-meson cmake gettext libglib2.0-dev libpolkit-gobject-1-dev xsltproc gobject-introspection libgirepository1.0-dev libgudev-1.0-dev libimobiledevice-dev libudev-dev udev}

if command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
    SUDO=sudo
else
    SUDO=
fi

$SUDO apt-get update
$SUDO apt-get install -y $BUILD_DEPENDS

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

if [ -n "${DEPENDS:-}" ]; then
    DEPENDS="libc6, libglib2.0-0, libgudev-1.0-0, libpolkit-gobject-1-0, $DEPENDS"
else
    DEPENDS="libc6, libglib2.0-0, libgudev-1.0-0, libpolkit-gobject-1-0"
fi

STAGE_REPO_DIR="$OUTPUT_DIR/${PACKAGE_NAME}-${PACKAGE_VERSION}"
PKG_DIR="$OUTPUT_DIR/pkgroot"
DEB_PATH="$OUTPUT_DIR/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCH}.deb"

mkdir -p "$OUTPUT_DIR"

rm -rf "$STAGE_REPO_DIR" "$PKG_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.deb' -delete

mkdir -p "$STAGE_REPO_DIR" "$PKG_DIR/DEBIAN"

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

meson setup "$STAGE_REPO_DIR/build" "$STAGE_REPO_DIR" -Dgtk-doc=false -Dman=false
meson compile -C "$STAGE_REPO_DIR/build"
DESTDIR="$PKG_DIR" meson install -C "$STAGE_REPO_DIR/build" --no-rebuild

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
 T2-focused UPower build packaged from a staged repository snapshot.
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

printf 'Installed-Size: %s\n' "$(du -sk "$PKG_DIR" | awk '{print $1}')" >>"$PKG_DIR/DEBIAN/control"

dpkg-deb --root-owner-group --build "$PKG_DIR" "$DEB_PATH"

printf 'Staged repo copy in %s\n' "$STAGE_REPO_DIR"
printf 'Built %s\n' "$DEB_PATH"

if [ "$INSTALL" -eq 1 ]; then
    if command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
        sudo dpkg -i "$DEB_PATH"
    else
        dpkg -i "$DEB_PATH"
    fi
fi
