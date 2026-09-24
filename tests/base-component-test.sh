#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/build-base-component.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/base-component.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
V="$w/vol"
stage() {  # $1 version: lay down what the payload would, then run its postinstall
  mkdir -p "$V/usr/local/mavergreen/.base/$1"
  sed "s/@MAVERGREEN_VERSION@/$1/" "$here/../scripts/mavergreen.sh" > "$V/usr/local/mavergreen/.base/$1/mavergreen"
  printf '/usr/local/mavergreen/bin\n/usr/local/mavergreen/sbin\n' > "$V/usr/local/mavergreen/.base/$1/paths"
  printf '/usr/local/mavergreen/share/man\n' > "$V/usr/local/mavergreen/.base/$1/manpaths"
  sh "$S" --emit-postinstall "$w/post-$1" --version "$1"
  sh "$w/post-$1" /fake.pkg "$V/" "$V/"
}
stage 1.0.9
[ "$(sh "$V/usr/local/bin/mavergreen" version)" = 1.0.9 ] || fail "a first install puts the helper in /usr/local/bin"
[ "$(cat "$V/etc/paths.d/mavergreen")" = "$(printf '/usr/local/mavergreen/bin\n/usr/local/mavergreen/sbin')" ] || fail "paths.d names both farm bin dirs"
[ -f "$V/etc/manpaths.d/mavergreen" ] || fail "manpaths.d is installed"
[ ! -e "$V/usr/local/mavergreen/.base/1.0.9" ] || fail "the staged copy is cleared"
stage 1.0.10
[ "$(sh "$V/usr/local/bin/mavergreen" version)" = 1.0.10 ] || fail "1.0.10 is newer than 1.0.9 -- the comparison is numeric, not lexical"
stage 1.0.9
[ "$(sh "$V/usr/local/bin/mavergreen" version)" = 1.0.10 ] || fail "an older product installer must never downgrade the helper"
[ ! -e "$V/usr/local/mavergreen/.base/1.0.9" ] || fail "a skipped older base still clears its staged copy"
printf 'garbage\n' > "$V/usr/local/mavergreen/.base/installed-version"
out="$(stage 1.0.9 2>&1)"
[ "$(sh "$V/usr/local/bin/mavergreen" version)" = 1.0.9 ] || fail "a non-numeric installed-version must be treated as missing, not compared -- an older base still installs over it"
[ "$(cat "$V/usr/local/mavergreen/.base/installed-version")" = 1.0.9 ] || fail "installed-version is rewritten after installing over a non-numeric value"
case "$out" in *"integer expression expected"*) fail "a non-numeric installed-version must not reach the numeric comparison: $out" ;; esac
rm "$V/usr/local/bin/mavergreen"; stage 1.0.9
[ -x "$V/usr/local/bin/mavergreen" ] || fail "a missing helper is reinstalled even from an older base"
out="$(sh "$w/post-1.0.9" 2>&1)" && fail "no target volume must fail rather than assume /: $out"
sh "$S" --out "$w/x.pkg" --version 'v1.0' 2>/dev/null && fail "a non-numeric version must be refused -- the compare is numeric"
if command -v pkgbuild >/dev/null 2>&1; then
  sh "$S" --version 1.0.9 --out "$w/base.pkg" >/dev/null 2>&1 || fail "the component must build"
  pkgutil --expand "$w/base.pkg" "$w/x"
  grep -q 'identifier="dev.mavergreen.base"' "$w/x/PackageInfo" || fail "the component is dev.mavergreen.base"
  (cd "$w/x" && gzip -dc Payload | cpio -it 2>/dev/null) | grep -qx './usr/local/mavergreen/.base/1.0.9/mavergreen' \
    || fail "the payload stages the helper under .base/<version>/"
fi
echo "PASS: base-component"
