#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
CF="$here/../scripts/carry-forward.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/carry-forward.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
MAVERGREEN_RELEASES="file://$w/srv"; SHIPYARD_FETCH_BACKOFF=0; SHIPYARD_FETCH_TRIES=1
export MAVERGREEN_RELEASES SHIPYARD_FETCH_BACKOFF SHIPYARD_FETCH_TRIES
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

T=1.0-mavergreen.1
P="$w/srv/Mavergreen/w/releases/download/$T"; mkdir -p "$P"
cat > "$P/w.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Widget 2</title>
    <item>
      <title>Widget 1.0</title>
      <sparkle:shortVersionString>1.0-mavergreen.1</sparkle:shortVersionString>
    </item>
  </channel>
</rss>
XML
printf '%s  w.xml\n' "$(sha "$P/w.xml")" > "$P/SHA256SUMS"

dist() {
  rm -rf "$w/dist"; mkdir -p "$w/dist"
  for f in w.xml w-1.0-mavergreen.2.pkg w-1.0-mavergreen.2-macos-x86_64.tar.gz w-1.0-mavergreen.2-linux-x86_64.tar.gz w-1.0-mavergreen.2-dSYM.tar.gz \
           x.xml x-1.0-mavergreen.2.pkg x-1.0-mavergreen.2-dSYM.tar.gz w-x.xml w-x-1.0-mavergreen.2.pkg; do
    printf 'new %s\n' "$f" > "$w/dist/$f"
  done
  printf '## Widget 1.0\nRelease 1.0-mavergreen.2\n\n### What changed\n- x moved\n' > "$w/dist/RELEASE_NOTES.md"
}
printf 'publish\nproduct w carry %s\nproduct w-x changed\nproduct x changed\n\nsummary\n' "$T" > "$w/decision"

dist
rc=0; sh "$CF" "$w/dist" Mavergreen/w "$w/decision" > "$w/out" 2> "$w/err" || rc=$?
[ "$rc" -eq 0 ] || fail "carrying w exits 0: rc $rc: $(cat "$w/err")"
cmp -s "$w/dist/w.xml" "$P/w.xml" || fail "w.xml is the previous release's, byte for byte"
for f in w-1.0-mavergreen.2.pkg w-1.0-mavergreen.2-macos-x86_64.tar.gz w-1.0-mavergreen.2-linux-x86_64.tar.gz w-1.0-mavergreen.2-dSYM.tar.gz; do
  [ "$(cat "$w/dist/$f")" = "new $f" ] || fail "a carried product's rebuilt $f stays in the release, so every product is under one tag"
done
for f in x.xml x-1.0-mavergreen.2.pkg x-1.0-mavergreen.2-dSYM.tar.gz w-x.xml w-x-1.0-mavergreen.2.pkg; do
  [ -e "$w/dist/$f" ] || fail "a changed product's $f stays, w-x's included"
done
[ "$(tail -n 1 "$w/dist/RELEASE_NOTES.md")" = "- Widget 2: unchanged, still 1.0-mavergreen.1" ] \
  || fail "the notes end with the unchanged line: $(cat "$w/dist/RELEASE_NOTES.md")"
grep -qx '### Unchanged' "$w/dist/RELEASE_NOTES.md" || fail "the unchanged lines sit under ### Unchanged"
echo "ok: a carried product's feed is the previous release's, and its rebuilt assets stay"

dist
printf '0000000000000000000000000000000000000000000000000000000000000000  w.xml\n' > "$P/SHA256SUMS"
rc=0; sh "$CF" "$w/dist" Mavergreen/w "$w/decision" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "a feed that does not match SHA256SUMS exits 1, got $rc"
echo "ok: a feed that does not verify is never carried"

rc=0; sh "$CF" "$w/dist" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "a usage error exits 2, got $rc"
echo "PASS: carry-forward"
