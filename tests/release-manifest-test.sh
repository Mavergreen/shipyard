#!/bin/sh
# platform: host-agnostic
set -eu
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
here="$(cd "$(dirname "$0")" && pwd)"
RM="$here/../scripts/release-manifest.sh"
FX="$here/fixtures/macho"
w="$(mktemp -d "${TMPDIR:-/tmp}/release-manifest.XXXXXX")"; trap 'chmod -R u+rwX "$w" 2>/dev/null; rm -rf "$w"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh failed -- the dylib rows read a pkg"
readers() {
  ( SELF="$here/../scripts"
    . "$SELF/mavergreen-meta.sh"; . "$SELF/lib/name-rules.sh"; . "$SELF/lib/macho-tools.sh"
    mach_tool LIPO >/dev/null 2>&1 && mach_tool OTOOL >/dev/null 2>&1 )
}

R="$w/repo"; M="$R/.mavergreen"
mkdir -p "$M/ingredients/zlib" "$M/ingredients/zlib-headers" "$M/ingredients/tool" \
  "$M/products/w/requires/libcxx22" "$M/products/v" "$M/deviations/relocatable/w"
printf '1.3.1\n# renovate: datasource=github-tags depName=madler/zlib\n' > "$M/ingredients/zlib/VERSION"
printf 'zlib\n' > "$M/ingredients/zlib-headers/from"
printf 'v2.0@0123456789abcdef0123456789abcdef01234567\n' > "$M/ingredients/tool/PIN"
mkdir -p "$M/ingredients/untracked-one"; printf 'yes\n' > "$M/ingredients/untracked-one/untracked"
printf 'W\n' > "$M/products/w/noun"; printf 'V\n' > "$M/products/v/noun"
printf 'library\n' > "$M/products/w/requires/libcxx22/kind"
printf '22.1.8\n' > "$M/products/w/requires/libcxx22/min"
printf 'w\n' > "$M/deviations/relocatable/w/scope"
printf 'w runs from any directory\n' > "$M/deviations/relocatable/w/reason"
printf 'w hardcodes its prefix\n' > "$M/deviations/relocatable/w/revisit"

mkdir -p "$w/root/opt/mavergreen/w/lib" "$w/dist"
cp "$FX/libw" "$w/root/opt/mavergreen/w/lib/libw.dylib"
printf 'text\n' > "$w/root/opt/mavergreen/w/lib/README"
"$SD" component --root "$w/root" --identifier dev.mavergreen.w --version 1.0.1 --install-location / \
  --mtime "$SOURCE_DATE_EPOCH" --out "$w/dist/w-1.0-mavergreen.1.pkg" >/dev/null

run() { rc=0; sh "$RM" "$@" > "$w/out" 2> "$w/err" || rc=$?; out="$(cat "$w/out")"; err="$(cat "$w/err")"; }
SHIPYARD_VERSION=1.0.900; export SHIPYARD_VERSION
want='ingredient tool v2.0@0123456789abcdef0123456789abcdef01234567
ingredient zlib 1.3.1
ingredient zlib-headers from zlib
relocatable w
requires w libcxx22 library 22.1.8
shipyard 1.0.900'
if readers; then
  run "$w/dist" 1.0-mavergreen.1 "$R"
  [ "$rc" -eq 0 ] || fail "release-manifest.sh exits 0: rc $rc: $err"
  [ "$out" = "dylib w @rpath/libw.dylib
$want" ] || fail "the rows: got
$out"
  echo "ok: pins, requires, relocatable, install names and the shipyard version"
else
  echo "SKIP the dylib row: no LLVM Mach-O readers here"
fi
rm -f "$w/dist"/*.pkg
run "$w/dist" 1.0-mavergreen.1 "$R"
[ "$rc" -eq 0 ] || fail "a dist with no pkg exits 0: rc $rc: $err"
[ "$out" = "$want" ] || fail "with no pkg, every row but the dylib rows: got
$out"
printf '*\n' > "$M/deviations/relocatable/w/scope"
run "$w/dist" 1.0-mavergreen.1 "$R"
printf '%s\n' "$out" | grep -qx 'relocatable v' || fail "a relocatable deviation scoped * names every product: $out"
echo "ok: a scope of * makes every product relocatable"

printf 'not a pkg\n' > "$w/dist/w-1.0-mavergreen.1.pkg"
run "$w/dist" 1.0-mavergreen.1 "$R"
[ "$rc" -eq 1 ] && [ -z "$out" ] || fail "an unreadable pkg exits 1, printing nothing: rc $rc: $out"
rc=0; sh "$RM" "$w/dist" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "a usage error exits 2: rc $rc"
echo "PASS: release-manifest"
