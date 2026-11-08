#!/bin/sh
# platform: host-agnostic
#   usage: fetch-drydock-test.sh
# spec: scripts/fetch_drydock.sh header -- the Linux archive of the pinned release is fetched, verified against the pinned
#       digest, unpacked once and kept; a digest that does not match fails; a malformed pin is a usage error; a Mac
#       uses an installed Drydock at the pinned version; MAVERGREEN_DRYDOCK_PREFIX is used as given, once checked. The
#       release is a file:// fixture tree (MAVERGREEN_RELEASES), so nothing reaches the network.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fetch-drydock-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
T=$(cd "$T" && pwd -P)
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [ ! -f "$T/err" ] || sed 's/^/    | /' "$T/err"; fails=$((fails + 1)); }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -c1-64; }
unset MAVERGREEN_DRYDOCK_PREFIX MAVERGREEN_DRYDOCK_INSTALLED
MAVERGREEN_DRYDOCK_CACHE="$T/cache"; MAVERGREEN_TAR_CACHE="$T/tars"; MAVERGREEN_RELEASES="file://$T/rel"
export MAVERGREEN_DRYDOCK_CACHE MAVERGREEN_TAR_CACHE MAVERGREEN_RELEASES

# spec: scripts/fetch_drydock.sh header -- a release v9.9.9 whose Linux archive is laid out as Drydock's: drydock-9.9.9/{bin,share}.
mkdir -p "$T/a/drydock-9.9.9/bin" "$T/a/drydock-9.9.9/share/drydock/objc/reference" "$T/rel/Mavergreen/drydock/releases/download/v9.9.9"
printf '#!/bin/sh\necho fixture drydock-objc\n' >"$T/a/drydock-9.9.9/bin/drydock-objc"; chmod +x "$T/a/drydock-9.9.9/bin/drydock-objc"
echo '{}' >"$T/a/drydock-9.9.9/share/drydock/objc/reference/manifest.json"
asset=drydock-9.9.9-linux-x86_64.tar.gz
(cd "$T/a" && tar -czf "$T/rel/Mavergreen/drydock/releases/download/v9.9.9/$asset" drydock-9.9.9)
mkdir -p "$T/pin"
printf 'v9.9.9\n' >"$T/pin/version"
printf '%s  %s\n' "$(sha "$T/rel/Mavergreen/drydock/releases/download/v9.9.9/$asset")" "$asset" >"$T/pin/linux-sha256"
fetch() { rc=0; out=$(env "$@" sh "$ROOT/scripts/fetch_drydock.sh" "$T/pin" 2>"$T/err") || rc=$?; }

fetch MAVERGREEN_DRYDOCK_HOST=linux
if [ "$rc" = 0 ] && [ -x "$out/bin/drydock-objc" ] && [ -f "$out/share/drydock/objc/reference/manifest.json" ]; then
  pass 'the Linux archive is fetched, verified and unpacked to a prefix holding bin/drydock-objc'
else fail "Linux fetch: exit $rc, printed '$out'"; fi
first=$out
rm -rf "$T/rel"
fetch MAVERGREEN_DRYDOCK_HOST=linux
[ "$rc" = 0 ] && [ "$out" = "$first" ] && pass 'an unpacked release is kept and reused without a fetch' ||
  fail "reuse: exit $rc, printed '$out', want $first"

rm -rf "$T/cache" "$T/tars"
mkdir -p "$T/rel/Mavergreen/drydock/releases/download/v9.9.9"
echo tampered >"$T/a/drydock-9.9.9/bin/extra"
(cd "$T/a" && tar -czf "$T/rel/Mavergreen/drydock/releases/download/v9.9.9/$asset" drydock-9.9.9)
fetch MAVERGREEN_DRYDOCK_HOST=linux
[ "$rc" = 1 ] && [ -z "$out" ] && pass 'an archive that does not match the pinned digest fails' ||
  fail "digest mismatch: exit $rc, printed '$out', want 1"

printf 'v9.9.9 && rm\n' >"$T/pin/version"
fetch MAVERGREEN_DRYDOCK_HOST=linux
[ "$rc" = 2 ] && pass 'a malformed version pin is a usage error' || fail "malformed pin: exit $rc, want 2"
printf 'v9.9.9\n' >"$T/pin/version"
: >"$T/pin/linux-sha256"
fetch MAVERGREEN_DRYDOCK_HOST=linux
[ "$rc" = 1 ] && grep -q 'linux-sha256' "$T/err" && pass 'a Linux pin with no digest fails, naming linux-sha256' ||
  fail "no digest: exit $rc"

mkdir -p "$T/inst/bin"
cp "$T/a/drydock-9.9.9/bin/drydock-objc" "$T/inst/bin/"
printf '<plist><dict>\n  <key>version</key>\n  <string>9.9.9</string>\n</dict></plist>\n' >"$T/inst/mavergreen.plist"
fetch MAVERGREEN_DRYDOCK_HOST=mac MAVERGREEN_DRYDOCK_INSTALLED="$T/inst"
[ "$rc" = 0 ] && [ "$out" = "$T/inst" ] && pass 'a Mac uses an installed Drydock at the pinned version' ||
  fail "installed: exit $rc, printed '$out', want $T/inst"

fetch MAVERGREEN_DRYDOCK_PREFIX="$T/inst"
[ "$rc" = 0 ] && [ "$out" = "$T/inst" ] && pass 'MAVERGREEN_DRYDOCK_PREFIX is used as given' || fail "prefix: exit $rc, printed '$out'"
fetch MAVERGREEN_DRYDOCK_PREFIX="$T/a"
[ "$rc" = 1 ] && [ -z "$out" ] && pass 'a MAVERGREEN_DRYDOCK_PREFIX with no bin/drydock-objc fails' ||
  fail "bad prefix: exit $rc, printed '$out', want 1"

[ "$fails" = 0 ] && echo 'fetch-drydock-test: all passed' || { echo "fetch-drydock-test: $fails failed"; exit 1; }
