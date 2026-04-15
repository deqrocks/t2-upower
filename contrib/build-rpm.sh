#!/bin/sh

set -eu

usage() {
    cat <<EOF
Usage: $0 [build-dir] [output-dir]

Build an RPM package from an existing Meson build directory.

Environment overrides:
  PACKAGE_NAME    RPM package name (default: t2-upower)
  PACKAGE_VERSION Package version (default: parsed from meson.build)
  PACKAGE_RELEASE RPM release value (default: 1)
  LICENSE         RPM License field (default: GPLv2+)
  SUMMARY         RPM Summary field
  DESCRIPTION     RPM description body
  URL             RPM URL field
  REQUIRES        Extra RPM dependencies
  NO_COMPILE      Set to 1 to skip 'meson compile'
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

BUILD_DIR=${1:-build}
OUTPUT_DIR=${2:-"$BUILD_DIR/rpm"}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if ! command -v meson >/dev/null 2>&1; then
    echo "error: meson is required" >&2
    exit 1
fi

if ! command -v rpmbuild >/dev/null 2>&1; then
    echo "error: rpmbuild is required" >&2
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
PACKAGE_RELEASE=${PACKAGE_RELEASE:-1}
LICENSE=${LICENSE:-GPLv2+}
SUMMARY=${SUMMARY:-T2-focused UPower build}
DESCRIPTION=${DESCRIPTION:-UPower fork with T2-specific suspend and keyboard-backlight fixes.}
URL=${URL:-https://github.com/deqrocks/t2-upower}

if [ -z "$PACKAGE_VERSION" ]; then
    echo "error: failed to determine package version from meson.build" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

TMPDIR_ROOT=$(mktemp -d)
cleanup() {
    rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT INT TERM

RPMTOPDIR="$TMPDIR_ROOT/rpmbuild"
STAGE_DIR="$TMPDIR_ROOT/stage"
SPECFILE="$TMPDIR_ROOT/${PACKAGE_NAME}.spec"
FILELIST="$TMPDIR_ROOT/files.list"

mkdir -p "$RPMTOPDIR/BUILD" "$RPMTOPDIR/BUILDROOT" "$RPMTOPDIR/RPMS" "$RPMTOPDIR/SOURCES" "$RPMTOPDIR/SPECS" "$RPMTOPDIR/SRPMS" "$STAGE_DIR"

if [ "${NO_COMPILE:-0}" != "1" ]; then
    meson compile -C "$BUILD_DIR"
fi

DESTDIR="$STAGE_DIR" meson install -C "$BUILD_DIR" --no-rebuild

find "$STAGE_DIR" -mindepth 1 -type d | sort | sed "s|$STAGE_DIR|%dir |" >"$FILELIST"
find "$STAGE_DIR" -mindepth 1 \( -type f -o -type l \) | sort | sed "s|$STAGE_DIR||" >>"$FILELIST"

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
cp -a "$STAGE_DIR"/. %{buildroot}/

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

find "$OUTPUT_DIR" -type f -name '*.rpm' -print | sort
