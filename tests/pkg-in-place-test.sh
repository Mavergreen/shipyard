#!/bin/sh
# platform: host-agnostic
# spec: scripts/assert_pkg_installs_in_place.sh -- reads a built pkg's PackageInfo with bsdtar, so the
#       gate runs on any host; the pkgs are the checked-in ones in tests/fixtures/checks/pkg-in-place.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
G="$here/../scripts/assert_pkg_installs_in_place.sh"
fx="$here/fixtures/checks/pkg-in-place"
PKG=ed25519-1.0.0-mavericks.1.pkg
w="$(mktemp -d "${TMPDIR:-/tmp}/pkg-in-place-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
unset SHIPYARD_CHECK_DIST

first_is() { case "$1" in "pkg-in-place: "*) ;; *) echo "FAIL $2: first line should start with 'pkg-in-place: ', got: $1"; exit 1 ;; esac; }

sh "$G" "$fx/pass/dist/$PKG" >/dev/null 2>&1 || { echo "FAIL a pkg built through build_component_pkg.sh must pass"; exit 1; }

out="$(sh "$G" "$fx/fail/dist/$PKG" 2>&1)" && { echo "FAIL a plain pkgbuild pkg must be rejected"; exit 1; }
first_is "$out" "a plain pkgbuild pkg"
printf '%s\n' "$out" | grep -q 'BundleIsRelocatable is ON' || { echo "FAIL should say BundleIsRelocatable is ON: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'BundleIsVersionChecked is ON' || { echo "FAIL should say BundleIsVersionChecked is ON: $out"; exit 1; }

out="$(sh "$G" "$w/does-not-exist.pkg" 2>&1)" && { echo "FAIL a missing pkg must fail rather than pass vacuously"; exit 1; }
first_is "$out" "a missing pkg"

printf 'not a pkg\n' > "$w/text.pkg"
out="$(sh "$G" "$w/text.pkg" 2>&1)" && { echo "FAIL a file that is no xar must fail, not pass for want of a PackageInfo"; exit 1; }
first_is "$out" "a file that is no xar"

mkdir -p "$w/dist"
cp "$fx/fail/dist/$PKG" "$w/dist/"
out="$(SHIPYARD_CHECK_DIST="$w/dist" sh "$G" 2>&1)" && { echo "FAIL under --dist the dist's pkgs are checked"; exit 1; }
first_is "$out" "--dist"

out="$(STEVEDORE=/nonexistent/stevedore sh "$G" "$fx/pass/dist/$PKG" 2>&1)" && { echo "FAIL with no usable stevedore the gate must fail, not pass"; exit 1; }
first_is "$out" "no stevedore"
printf '%s\n' "$out" | grep -q 'stevedore, which reads the pkgs, cannot be fetched' || { echo "FAIL the failure should say stevedore cannot be fetched: $out"; exit 1; }

echo "PASS: pkg-in-place"
