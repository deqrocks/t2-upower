#!/bin/sh

set -eu

usage() {
    cat <<EOF
Usage: $0 [-i|--install] [output-dir]

Build an RPM package in a staged repo copy.

Environment overrides:
  PACKAGE_NAME    RPM package name (default: t2-upower)
  PACKAGE_VERSION Package version (default: parsed from meson.build)
  PACKAGE_RELEASE RPM release value (default: 1)
  LICENSE         RPM License field (default: GPLv2+)
  SUMMARY         RPM Summary field
  DESCRIPTION     RPM description body
  URL             RPM URL field
  REQUIRES        Extra RPM dependencies
  BUILD_DEPENDS   Space-separated RPM packages to install before building
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

OUTPUT_DIR=${OUTPUT_DIR:-"$REPO_ROOT/pkg/fedora"}

BUILD_DEPENDS=${BUILD_DEPENDS:-meson rpm-build gcc cmake glib2-devel polkit-devel libxslt gobject-introspection-devel libgudev-devel libimobiledevice-devel systemd-devel}

if command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
    SUDO=sudo
else
    SUDO=
fi

if command -v dnf >/dev/null 2>&1; then
    $SUDO dnf makecache --refresh
    $SUDO dnf install -y $BUILD_DEPENDS
elif command -v yum >/dev/null 2>&1; then
    $SUDO yum makecache
    $SUDO yum install -y $BUILD_DEPENDS
else
    echo "error: dnf or yum is required to install build dependencies" >&2
    exit 1
fi

if ! command -v rpmbuild >/dev/null 2>&1; then
    echo "error: rpmbuild is required" >&2
    exit 1
fi

PACKAGE_NAME=${PACKAGE_NAME:-t2-upower}
PACKAGE_VERSION=${PACKAGE_VERSION:-$(
    sed -n "s/^[[:space:]]*version:[[:space:]]*'\\([^']*\\)'.*/\\1/p" "$REPO_ROOT/meson.build" | head -n 1
)}
PACKAGE_RELEASE=${PACKAGE_RELEASE:-1}
LICENSE=${LICENSE:-GPLv2+}
SUMMARY=${SUMMARY:-T2-focused UPower build}
DESCRIPTION=${DESCRIPTION:-UPower fork with T2-specific suspend and keyboard-backlight fixes.}
URL=${URL:-https://github.com/deqrocks/t2-upower}

if [ -z "$PACKAGE_VERSION" ]; then
    echo "error: failed to determine package version from meson.build" >&2
    exit 1
fi

STAGE_REPO_DIR="$OUTPUT_DIR/${PACKAGE_NAME}-${PACKAGE_VERSION}"
PKG_DIR="$OUTPUT_DIR/pkgroot"
RPMTOPDIR="$OUTPUT_DIR/rpmbuild"
SPECFILE="$OUTPUT_DIR/${PACKAGE_NAME}.spec"
FILELIST="$OUTPUT_DIR/files.list"

mkdir -p "$OUTPUT_DIR"

rm -rf "$STAGE_REPO_DIR" "$PKG_DIR" "$RPMTOPDIR"
find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.rpm' -delete
rm -f "$SPECFILE" "$FILELIST"

mkdir -p \
    "$STAGE_REPO_DIR" \
    "$PKG_DIR" \
    "$RPMTOPDIR/BUILD" \
    "$RPMTOPDIR/BUILDROOT" \
    "$RPMTOPDIR/RPMS" \
    "$RPMTOPDIR/SOURCES" \
    "$RPMTOPDIR/SPECS" \
    "$RPMTOPDIR/SRPMS"

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

find "$PKG_DIR" -mindepth 1 -type d | sort | sed "s|$PKG_DIR|%dir |" >"$FILELIST"
find "$PKG_DIR" -mindepth 1 \( -type f -o -type l \) | sort | sed "s|$PKG_DIR||" >>"$FILELIST"

if [ -n "${REQUIRES:-}" ]; then
    REQUIRES_LINE="Requires: $REQUIRES"
else
    REQUIRES_LINE=""
fi

cat >"$SPECFILE" <<EOF
Name:           $PACKAGE_NAME
Version:        $PACKAGE_VERSION
Release:        $PACKAGE_RELEASE%{?dist}
Summary:        $SUMMARY
License:        $LICENSE
URL:            $URL
Provides:       upower
Conflicts:      upower
Obsoletes:      upower
$REQUIRES_LINE

%description
$DESCRIPTION

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a "$PKG_DIR"/. %{buildroot}/

%post
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || :
    if systemctl is-enabled upower >/dev/null 2>&1 || systemctl is-active upower >/dev/null 2>&1; then
        systemctl restart upower >/dev/null 2>&1 || :
    fi
fi

%postun
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || :
fi

%files -f $FILELIST
EOF

rpmbuild \
    --define "_topdir $RPMTOPDIR" \
    --define "_rpmdir $OUTPUT_DIR" \
    -bb "$SPECFILE"

printf 'Staged repo copy in %s\n' "$STAGE_REPO_DIR"
RPM_PATH=$(find "$OUTPUT_DIR" -type f -name '*.rpm' | sort | tail -n 1)

if [ -n "$RPM_PATH" ]; then
    printf '%s\n' "$RPM_PATH"
fi

if [ "$INSTALL" -eq 1 ] && [ -n "$RPM_PATH" ]; then
    if command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
        sudo rpm -Uvh --replacepkgs "$RPM_PATH"
    else
        rpm -Uvh --replacepkgs "$RPM_PATH"
    fi
fi
