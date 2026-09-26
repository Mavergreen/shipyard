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
for v in 2.0 3.0 1.0; do
  d="$W/pkg$v"; mkdir -p "$d/DEBIAN"
  printf 'Package: demo\nVersion: %s\nArchitecture: amd64\nMaintainer: x\nDescription: x\n' "$v" > "$d/DEBIAN/control"
  case $v in
    2.0) i="$d/usr/share/icons/hicolor/512x512/apps" ;;
    3.0) i="$d/usr/share/icons/hicolor/512x512/extra/apps" ;;
    1.0) i= ;;
  esac
  [ -z "$i" ] || { mkdir -p "$i"; cp "$W/good.png" "$i/demo.png"; }
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

deep='/usr/share/icons/hicolor/*/*/apps/demo.png'
conf "file://$W/good.png" "$deep";                                    ok "both sources work, and the newest version (listed mid-way) is the one checked"
conf "file://$W/gone.png" "$deep";                                    no "a 404 ICON_URL" ICON_URL
conf "file://$W/page.png" "$deep";                                    no "a non-PNG ICON_URL" ICON_URL
conf "file://$W/good.png" '/opt/moved/*.png';                         no "an ICON_GLOB the package no longer has" ICON_GLOB
conf "file://$W/good.png" '/usr/share/icons/hicolor/*/apps/demo.png'; no "an icon moved one directory deeper (a * never crosses /)" ICON_GLOB
conf "" "$deep";                                                      ok "no ICON_URL is fine"
echo "ok check-preset-icons"
