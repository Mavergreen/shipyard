#!/bin/sh
# platform: host-agnostic -- needs dpkg-deb to build its fixture package; exits 77 without it
# spec: scripts/check-preset-icons.sh -- fixtures are file:// URLs and a two-version apt repo built here
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-preset-icons.sh"
for t in curl dpkg-deb dpkg; do
  command -v "$t" >/dev/null 2>&1 || { echo "SKIP: needs $t"; exit 77; }
done
W=$(mktemp -d "${TMPDIR:-/tmp}/cpi-test.XXXXXX"); trap 'rm -rf "$W"' EXIT

printf '\211PNG\r\n\032\n' > "$W/good.png"; printf '<html/>' > "$W/page.png"
mkdir -p "$W/repo/dists/stable/main/binary-amd64" "$W/repo/pool"
for v in 1.0 2.0; do
  d="$W/pkg$v"; mkdir -p "$d/DEBIAN" "$d/usr/share/icons/hicolor/512x512/apps"
  printf 'Package: demo\nVersion: %s\nArchitecture: amd64\nMaintainer: x\nDescription: x\n' "$v" > "$d/DEBIAN/control"
  if [ "$v" = 2.0 ]; then cp "$W/good.png" "$d/usr/share/icons/hicolor/512x512/apps/demo.png"; fi
  dpkg-deb -b "$d" "$W/repo/pool/demo_$v.deb" >/dev/null
  printf 'Package: demo\nVersion: %s\nFilename: pool/demo_%s.deb\n\n' "$v" "$v" >> "$W/repo/dists/stable/main/binary-amd64/Packages"
done
conf() {
  printf "APT_KEY_URL=file://%s/key\nAPT_REPO='deb [arch=amd64 signed-by=/x.gpg] file://%s/repo stable main'\nAPT_PKGS='demo extra'\nICON_URL=%s\nICON_GLOB='%s'\n" \
    "$W" "$W" "$1" "$2" > "$W/demo.conf"
}
ok() { sh "$S" "$W/demo.conf" >/dev/null 2>&1 || { echo "FAIL $1: expected pass"; sh "$S" "$W/demo.conf"; exit 1; }; }
no() {
  out=$(sh "$S" "$W/demo.conf" 2>&1) && { echo "FAIL $1: expected failure"; exit 1; }
  printf '%s\n' "$out" | grep -q "$2" || { echo "FAIL $1: should mention $2, got: $out"; exit 1; }
}

conf "file://$W/good.png" '/usr/share/icons/hicolor/*/apps/demo.png'; ok "both sources work, and the newest version is the one checked"
conf "file://$W/gone.png" '/usr/share/icons/hicolor/*/apps/demo.png'; no "a 404 ICON_URL" ICON_URL
conf "file://$W/page.png" '/usr/share/icons/hicolor/*/apps/demo.png'; no "a non-PNG ICON_URL" ICON_URL
conf "file://$W/good.png" '/opt/moved/*.png';                          no "an ICON_GLOB the package no longer has" ICON_GLOB
conf "" '/usr/share/icons/hicolor/*/apps/demo.png';                     ok "no ICON_URL is fine"
echo "ok check-preset-icons"
