#!/bin/sh
# platform: host-agnostic
#   usage: fetch-verify-stamp-test.sh
#          fetch_product_tar.sh verifies an unpacked pin once, then trusts its stamp until the pin or the
#          tree changes -- against a file:// fixture, counting calls to the SHA-256 tools.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
H="$here/../scripts/fetch_product_tar.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/fetch-verify-stamp-test.XXXXXX")"; trap 'chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mkdir -p "$w/shim" "$w/rel/Mavergreen/widget-repo/releases/download/1.0" "$w/src/opt/mavergreen/widget/bin"
for t in shasum sha256sum openssl; do
  real="$(command -v "$t" || :)"
  [ -n "$real" ] || continue
  printf '#!/bin/sh\necho x >> "%s/calls"\nexec "%s" "$@"\n' "$w" "$real" > "$w/shim/$t"
  chmod +x "$w/shim/$t"
done
printf 'widget dev.mavergreen.widget widget-repo\n' > "$w/names"
printf 'W\n' > "$w/src/opt/mavergreen/widget/bin/tool"; chmod 755 "$w/src/opt/mavergreen/widget/bin/tool"
printf 'data\n' > "$w/src/opt/mavergreen/widget/data"
rel="$w/rel/Mavergreen/widget-repo/releases/download/1.0"
( cd "$w/src" && tar -czf "$rel/widget-1.0-linux-x86_64.tar.gz" opt ) || exit 1
sha="$(shasum -a 256 "$rel/widget-1.0-linux-x86_64.tar.gz" | awk '{print $1}')"
printf '%s  widget-1.0-linux-x86_64.tar.gz\n' "$sha" > "$rel/SHA256SUMS"
: > "$w/calls"
fetch() {
  : > "$w/calls"
  MAVERGREEN_PRODUCT_NAMES="$w/names" MAVERGREEN_RELEASES="file://$w/rel" MAVERGREEN_TAR_CACHE="$w/cache" \
    PATH="$w/shim:$PATH" sh "$H" widget 1.0 "$w/out/widget" >/dev/null 2>&1
}
calls() { wc -l < "$w/calls" | tr -d ' '; }

fetch || fail "the first fetch must succeed"
[ "$(calls)" -ge 1 ] || fail "the first fetch must verify, saw $(calls) hash calls"
fetch || fail "the second fetch must succeed"
[ "$(calls)" -eq 0 ] || fail "the second fetch of an unchanged tree must verify zero times, saw $(calls)"

sleep 1
printf 'tampered\n' > "$w/out/widget/data"
if fetch; then fail "a modified tree must not pass"; fi
[ "$(calls)" -ge 1 ] || fail "a modified tree must be re-verified"

rm -rf "$w/out"
fetch || fail "a fresh unpack must succeed"
rm -f "$w/out/widget/.mavergreen-tree-verified"
fetch || fail "a fetch without the stamp must succeed"
[ "$(calls)" -ge 1 ] || fail "a fetch without the stamp must re-verify"
fetch || fail "the fetch after re-stamping must succeed"
[ "$(calls)" -eq 0 ] || fail "a re-stamped tree must verify zero times, saw $(calls)"
touch -r "$w/out/widget/data" "$w/mtime-ref"
sleep 1
printf 'DATA\n' > "$w/out/widget/data"
touch -r "$w/mtime-ref" "$w/out/widget/data"
if fetch; then fail "a same-size rewrite with its mtime restored must not pass"; fi
[ "$(calls)" -ge 1 ] || fail "a same-size rewrite with its mtime restored must be re-verified"
rm -rf "$w/out"
fetch || fail "a fresh unpack after the rewrite must succeed"
fetch || fail "the fetch that re-stamps must succeed"
rm -f "$w/out/widget/.mavergreen-tree-verified"
chmod a-w "$w/out/widget"
fetch || fail "a tree that cannot be stamped must still fetch"
[ "$(calls)" -ge 1 ] || fail "an unstampable tree must be re-verified"
fetch || fail "an unstampable tree must keep fetching"
[ "$(calls)" -ge 1 ] || fail "an unstampable tree must keep re-verifying"
chmod u+w "$w/out/widget"
echo PASS
