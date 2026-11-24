#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
DM="$here/../scripts/dep-manifest.sh"
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/dep-manifest.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
export MAVERGREEN_RELEASES="file://$w/rel" MAVERGREEN_REPO_ROOT="$w/repo" XDG_CACHE_HOME="$w/cache" SHIPYARD_FETCH_BACKOFF=0
pin() {  # pin DEP REPO VERSION
  mkdir -p "$w/repo/.mavergreen/ingredients/$1"
  printf '%s\n' "$2" > "$w/repo/.mavergreen/ingredients/$1/REPO"
  printf '%s\n# renovate: datasource=github-releases depName=%s\n' "$3" "$2" > "$w/repo/.mavergreen/ingredients/$1/VERSION"
}
serve() {  # serve REPO TAG [MANIFEST-TEXT]: a release whose SHA256SUMS lists a pkg, and the manifest when given
  _d="$w/rel/Mavergreen/$1/releases/download/$2"; mkdir -p "$_d"
  printf 'pkg' > "$_d/x.pkg"
  if [ $# -ge 3 ]; then printf '%s\n' "$3" > "$_d/RELEASE-MANIFEST.txt"; fi
  ( cd "$_d" && shasum -a 256 * > SHA256SUMS )
}
run() { rc=0; out="$(sh "$DM" "$@" 2>"$w/err")" || rc=$?; }

M='dylib libcxx22 @rpath/libc++.1.dylib
relocatable libcxx22
shipyard 1.0.880'
pin libcxx22 Mavergreen/clang-22 22.1.8-mavergreen.1
serve clang-22 22.1.8-mavergreen.1 "$M"
run libcxx22
[ "$rc" -eq 0 ] || fail "a served manifest: exit $rc, $(cat "$w/err")"
[ "$out" = "$M" ] || fail "a served manifest is printed as published: $out"
[ -f "$w/cache/mavergreen/release-manifests/clang-22/22.1.8-mavergreen.1" ] || fail "the manifest is cached under <repo>/<tag>"
rm -rf "$w/rel/Mavergreen/clang-22/releases/download/22.1.8-mavergreen.1"
run libcxx22
[ "$rc" -eq 0 ] && [ "$out" = "$M" ] || fail "a cached manifest needs no fetch: exit $rc, $out"
echo "ok: a pinned release's manifest is fetched, verified and cached"

pin zlib Mavergreen/zlib 1.3.1-mavergreen.2
serve zlib 1.3.1-mavergreen.2 'dylib zlib @rpath/libz.1.dylib'
printf 'dylib zlib /tampered\n' > "$w/rel/Mavergreen/zlib/releases/download/1.3.1-mavergreen.2/RELEASE-MANIFEST.txt"
run zlib
[ "$rc" -eq 1 ] || fail "a manifest that does not match SHA256SUMS: exit $rc, want 1"
[ ! -e "$w/cache/mavergreen/release-manifests/zlib/1.3.1-mavergreen.2" ] || fail "a refused manifest is not cached"
echo "ok: a manifest that does not match SHA256SUMS fails, uncached"

pin old Mavergreen/old 22.1.8-mavericks.28
serve old 22.1.8-mavericks.28
run old
[ "$rc" -eq 3 ] || fail "a -mavericks.N release with no manifest: exit $rc, want 3: $(cat "$w/err")"
grep -q 'has no RELEASE-MANIFEST.txt' "$w/err" || fail "exit 3 says why: $(cat "$w/err")"
grep -q 'until L1' "$w/err" || fail "exit 3 says the tolerance ends at L1: $(cat "$w/err")"
pin new Mavergreen/new 22.1.8-mavergreen.1
serve new 22.1.8-mavergreen.1
run new
[ "$rc" -eq 1 ] || fail "a -mavergreen.N release with no manifest fails closed: exit $rc, want 1"
pin own Mavergreen/own 20261027.1
serve own 20261027.1
run own
[ "$rc" -eq 3 ] || fail "an own-upstream release with no manifest: exit $rc, want 3"
echo "ok: only a -mavergreen.N pin with no manifest fails closed"

pin bare Mavergreen/bare 22.1.8-mavericks.3
mkdir -p "$w/rel/Mavergreen/bare/releases/tag"; printf 'release\n' > "$w/rel/Mavergreen/bare/releases/tag/22.1.8-mavericks.3"
run bare
[ "$rc" -eq 3 ] || fail "a -mavericks.N release with neither manifest nor SHA256SUMS: exit $rc, want 3"
echo "ok: a -mavericks.N release that predates SHA256SUMS exits 3"
pin gone Mavergreen/gone 22.1.8-mavericks.82
run gone
[ "$rc" -eq 1 ] || fail "a pin naming no release (deleted, or a typo) fails closed: exit $rc, want 1"
grep -q 'has no release 22.1.8-mavericks.82' "$w/err" || fail "exit 1 names the missing release: $(cat "$w/err")"
grep -q '/usr/local/mavergreen' "$w/err" && fail "a missing release is not taken as a pre-flag-day one: $(cat "$w/err")"
echo "ok: a release that does not exist is no pre-flag-day release"

pin child Mavergreen/unused 1.0
printf 'libcxx22\n' > "$w/repo/.mavergreen/ingredients/child/from"
run child
[ "$rc" -eq 0 ] && [ "$out" = "$M" ] || fail "a from ingredient reads its parent's release: exit $rc, $out"
echo "ok: a from ingredient reads its parent's pin"

run nosuch
[ "$rc" -eq 1 ] || fail "an ingredient the repo does not pin: exit $rc, want 1"
run
[ "$rc" -eq 2 ] || fail "no argument: exit $rc, want 2"
echo "PASS: dep-manifest"
