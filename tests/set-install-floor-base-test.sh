#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
command -v productbuild >/dev/null 2>&1 || { echo "no productbuild -- skipping"; exit 77; }
w="$(mktemp -d "${TMPDIR:-/tmp}/floor-base.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
mkdir -p "$w/root/usr/local/mavergreen/x" "$w/c"; echo x > "$w/root/usr/local/mavergreen/x/f"
pkgbuild --quiet --root "$w/root" --identifier dev.mavergreen.x --version 1.0 --install-location / "$w/c/x.pkg"
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X --component "$w/c/x.pkg" \
  --out "$w/out.pkg" --base-version 1.0.9 >/dev/null 2>&1 || fail "the archive must build"
pkgutil --expand "$w/out.pkg" "$w/x"
[ -d "$w/x/mavergreen-base.pkg" ] || fail "the archive carries the base component"
first="$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$w/x/Distribution" | grep -v '^default$' | head -1)"
[ "$first" = dev.mavergreen.base ] || fail "the base component is listed first, so its payload lands before the product's scripts run: got $first"
grep -q 'os-version min="10.9.5"' "$w/x/Distribution" || fail "the floor is still enforced"
echo "PASS: set-install-floor-base"
