#!/bin/sh
# platform: host-agnostic
#   usage: pkg-reader-test.sh
#          One pkg reader (stevedore), one Mach-O tool seam (mach_tool), and each pkg expanded once per
#          shipyard-check --dist: no script outside lib/ runs bsdtar on a pkg, lib/pkg-read.sh and
#          lib/mach-nm.sh are gone, a counting stub for `stevedore expand` sees one call per pkg across a
#          whole --dist run, and the three pkg readers each expand for themselves when run standalone.
#          Exits 77 without LLVM's Mach-O readers or a fetchable stevedore.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
. "$here/scripts/lib/macho-tools.sh"
. "$here/tests/lib/fixture_tree.sh"
fail() { echo "FAIL: $1"; exit 1; }

[ ! -e "$here/scripts/lib/pkg-read.sh" ] || fail "one pkg reader: scripts/lib/pkg-read.sh is still there"
[ ! -e "$here/scripts/lib/mach-nm.sh" ] || fail "one mach tool seam: scripts/lib/mach-nm.sh is still there"
hits="$(cd "$here" && git ls-files scripts .github | grep -v '^scripts/lib/' | while IFS= read -r f; do
  [ -f "$f" ] && grep -nE '^[^#]*bsdtar' "$f" | sed "s|^|$f:|"
done || true)"
[ -z "$hits" ] || fail "one pkg reader: bsdtar outside lib/: $hits"
hits="$(cd "$here" && git grep -nE 'shipyard_mach_nm|mach-nm\.sh' -- scripts tests | grep -v pkg-reader-test.sh || true)"
[ -z "$hits" ] || fail "one mach tool seam: shipyard_mach_nm is still named: $hits"
! grep -q libarchive-tools "$here/.github/workflows/linux-host.yml" || fail "linux-host.yml still installs libarchive-tools"

for v in LIPO OTOOL NM; do mach_tool $v >/dev/null 2>&1 || { echo "SKIP: no LLVM Mach-O readers"; exit 77; }; done
real="$(sh "$here/scripts/fetch_stevedore.sh" 2>/dev/null)" || { echo "SKIP: stevedore cannot be fetched"; exit 77; }

w="$(mktemp -d "${TMPDIR:-/tmp}/pkg-reader-test.XXXXXX")"; trap 'chmod -R u+rwX "$w" 2>/dev/null; rm -rf "$w"' EXIT
fx="$here/tests/fixtures/checks"
c="$w/repo"
fixture_tree "$fx" "$fx/artifact-facts/pass" "$c"
rm -f "$c/ENV"
cp "$c/dist/ed25519-1.0.0-mavericks.1.pkg" "$c/dist/second-1.0.0-mavericks.1.pkg"
cat > "$w/stevedore" <<STUB
#!/bin/sh
[ "\$1" != expand ] || echo "\$2" >> "$w/expands"
exec "$real" "\$@"
STUB
chmod +x "$w/stevedore"
: > "$w/expands"

(cd "$c" && STEVEDORE="$w/stevedore" SHIPYARD_CHECK_VERSION=1.0.0-mavericks.1 SHIPYARD_CHECK_REPO="$c" \
  sh "$here/scripts/shipyard-check" --dist "$c/dist" > "$w/out" 2>&1) || :
n="$(wc -l < "$w/expands" | tr -d ' ')"
[ "$n" = 2 ] || fail "--dist extracts each pkg once: two pkgs, $n expands: $(cat "$w/expands")"
[ "$(sort -u "$w/expands" | wc -l | tr -d ' ')" = 2 ] || fail "--dist extracts each pkg once: a pkg was expanded twice: $(cat "$w/expands")"

rm "$c/dist/second-1.0.0-mavericks.1.pkg"
for s in assert_pkg_installs_in_place.sh assert_gui_relaunch_safe.sh assert_binary_compatible.sh; do
  : > "$w/expands"
  (cd "$c" && STEVEDORE="$w/stevedore" SHIPYARD_CHECK_DIST="$c/dist" env -u SHIPYARD_CHECK_PKGS sh "$here/scripts/$s" > "$w/out" 2>&1) || :
  [ "$(wc -l < "$w/expands" | tr -d ' ')" = 1 ] || fail "standalone $s extracts for itself, once: $(cat "$w/expands")"
  ! grep -q 'cannot be read\|CANNOT MEASURE' "$w/out" || fail "standalone $s could not read the pkg: $(cat "$w/out")"
done
echo "PASS: pkg-reader"
