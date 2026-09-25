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
[ "$first" = dev.mavergreen.base ] || fail "the base component is listed first, so its postinstall installs or upgrades the helper before the product's postinstall runs it: got $first"
grep -q 'os-version min="10.9.5"' "$w/x/Distribution" || fail "the floor is still enforced"

real_pb="$(command -v productbuild)"; mkdir -p "$w/pbwrap"
{
  printf '#!/bin/sh\nprev=""\nfor a in "$@"; do\n'
  printf '  if [ "$prev" = --distribution ]; then cp "$a" "%s"; fi\n  prev="$a"\ndone\n' "$w/dist-as-written.xml"
  printf 'exec "%s" "$@"\n' "$real_pb"
} > "$w/pbwrap/productbuild"
chmod +x "$w/pbwrap/productbuild"
PATH="$w/pbwrap:$PATH" sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.x --title X \
  --component "$w/c/x.pkg" --out "$w/out-w.pkg" --base-version 1.0.9 >/dev/null 2>&1 || fail "the archive must build through the wrapper"
[ -f "$w/dist-as-written.xml" ] || fail "the test must capture the distribution set_install_floor.sh writes, or it proves nothing"
awk '{ n += gsub(/<line choice=/, "&"); if (gsub(/<line choice=/, "&") > 1) bad = 1 } END { exit !(n == 3 && !bad) }' "$w/dist-as-written.xml" \
  || fail "the distribution as written carries one <line choice=...> per line, so a line-oriented parse never depends on productbuild reformatting it: $(grep -n 'line choice' "$w/dist-as-written.xml")"

rc=0
sh "$here/../scripts/set_install_floor.sh" --identifier dev.mavergreen.base --title Base --component "$w/c/x.pkg" \
  --out "$w/out2.pkg" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "--identifier dev.mavergreen.base must be refused as a usage error (exit 2), since the base is added automatically and a caller passing it as the product identifier would collide with it; got $rc"
[ ! -e "$w/out2.pkg" ] || fail "a refused --identifier dev.mavergreen.base must not write an output pkg"

echo "PASS: set-install-floor-base"
