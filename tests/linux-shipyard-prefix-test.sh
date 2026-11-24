#!/bin/sh
# platform: host-agnostic
#   usage: linux-shipyard-prefix-test.sh
#          scripts/install-shipyard-prefix.sh, install@v1's Linux install, lays down exactly the pkg's
#          opt/mavergreen/shipyard: the same files, links and bytes as the Payload of a pkg
#          package-pkg.sh builds from the same checkout, which installs nothing outside the prefix and
#          ships the same manifest; both manifests name shipyard's feed. It links the exported names into opt/mavergreen/bin,
#          replaces an older install whole, leaves a root-owned tree when run as root, and without root
#          or sudo exits 1 having written nothing. SUDO=env and MAVERGREEN_CHAIN_UID stand in for root
#          off root. Exit 0 clean, 1 on failure, 77 with no cmake.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
S="$root/scripts"
command -v cmake > /dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/linux-shipyard-prefix.XXXXXX")"
trap 'chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT
w="$(cd -P "$w" && pwd)"
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
rel=opt/mavergreen/shipyard
MAVERGREEN_REPO_ROOT="$root"; GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-Mavergreen/shipyard}"
export MAVERGREEN_REPO_ROOT GITHUB_REPOSITORY
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH

mkdir "$w/r"
SUDO=env MAVERGREEN_CHAIN_UID="$(id -u)" sh "$S/install-shipyard-prefix.sh" --root "$w/r" --version 1.2.3 > "$w/out" 2> "$w/err" \
  || { echo "FAIL: install-shipyard-prefix.sh failed:"; sed 's/^/    | /' "$w/err"; exit 1; }
[ "$(cat "$w/out")" = "$w/r/$rel" ] || fail "it must print the prefix it installed, $w/r/$rel; got $(cat "$w/out")"

sh "$S/stage-shipyard-prefix.sh" --stage "$w/s" --build "$w/b" --version 1.2.3 > /dev/null 2> "$w/stage.log" \
  || { echo "FAIL: stage-shipyard-prefix.sh failed:"; sed 's/^/    | /' "$w/stage.log"; exit 1; }
sh "$S/package-pkg.sh" --shipyard-prefix "$w/s/$rel" --version 1.2.3 --dist "$w/o" > "$w/pkg.log" 2>&1 \
  || { echo "FAIL: package-pkg.sh failed:"; sed 's/^/    | /' "$w/pkg.log"; exit 1; }
STEVEDORE="$(sh "$S/fetch_stevedore.sh")"
sh "$S/pkg_read.sh" payload "$w/o/shipyard-1.2.3.pkg" dev.mavergreen.shipyard "$w/p" \
  || { echo "FAIL: could not unpack the pkg's Payload"; exit 1; }

listing() {  # $1 = tree: every entry, a link with its target, a file with its mode and checksum
  ( cd "$1" && find . ! -name mavergreen.plist | LC_ALL=C sort | while IFS= read -r e; do
      if [ -h "$e" ]; then printf '%s -> %s\n' "$e" "$(readlink "$e")"
      elif [ -d "$e" ]; then printf '%s/\n' "$e"
      else printf '%s %s %s\n' "$e" "$(ls -l "$e" | cut -c1-10)" "$(cksum < "$e")"; fi
    done )
}
key=share/cmake/MavergreenShipyard/keys/feed-ed25519.pub
for t in "$w/p/$rel" "$w/r/$rel"; do
  [ -s "$t/$key" ] && cmp -s "$t/$key" "$root/keys/feed-ed25519.pub" || fail "$t must carry $key, the family key, beside the scripts"
  [ ! -e "$t/share/cmake/MavergreenShipyard/RequireAppleClang.cmake" ] || fail "$t must not carry RequireAppleClang.cmake: MavergreenToolchain.cmake chooses the compiler"
done
listing "$w/p/$rel" > "$w/pkg.list"
listing "$w/r/$rel" > "$w/linux.list"
[ -s "$w/pkg.list" ] && [ "$(grep -c . "$w/pkg.list")" -gt 50 ] || fail "the pkg's prefix lists almost nothing: $(grep -c . "$w/pkg.list")"
if ! cmp -s "$w/pkg.list" "$w/linux.list"; then
  fail "the Linux-installed prefix differs from the pkg's Payload (< pkg, > Linux):"
  diff "$w/pkg.list" "$w/linux.list" | sed 's/^/    | /' | head -40
fi

( cd "$w/p" && find . \( -type f -o -type l \) ) | sed 's|^\./||' | grep -v "^$rel/" > "$w/outside" || :
[ ! -s "$w/outside" ] || { fail "the pkg installs nothing outside the prefix (no updater, no LaunchAgent); got:"; sed 's/^/    | /' "$w/outside"; }
( cd "$w/p" && find . -path './Library*' ) | grep -q . && fail "the pkg's payload has no path under Library/"
cmp -s "$w/p/$rel/mavergreen.plist" "$w/r/$rel/mavergreen.plist" \
  || { fail "the pkg's manifest and the Linux one differ:"; diff "$w/p/$rel/mavergreen.plist" "$w/r/$rel/mavergreen.plist" | sed 's/^/    | /'; }
[ "$("$STEVEDORE" plist get "$w/p/$rel/mavergreen.plist" feed 2>/dev/null || :)" = https://github.com/Mavergreen/shipyard/releases/latest/download/shipyard.xml ] \
  || fail "the pkg's manifest must name shipyard's feed"

farm="$(cd "$w/r/opt/mavergreen/bin" && for f in *; do printf '%s -> %s\n' "$f" "$(readlink "$f")"; done)"
want="shipyard-check -> ../shipyard/bin/shipyard-check
shipyard-cmake -> ../shipyard/bin/shipyard-cmake
shipyard-cpack -> ../shipyard/bin/shipyard-cpack
shipyard-ctest -> ../shipyard/bin/shipyard-ctest
shipyard-provision -> ../shipyard/bin/shipyard-provision
shipyard-scripts -> ../shipyard/bin/shipyard-scripts"
[ "$farm" = "$want" ] || fail "opt/mavergreen/bin must link exactly the pkg's exported shipyard-* names, never bare cmake/ctest/cpack; got
$farm"

SUDO=env MAVERGREEN_CHAIN_UID="$(id -u)" sh "$S/install-shipyard-prefix.sh" --root "$w/r" --version 1.2.4 > /dev/null 2> "$w/err" \
  || { fail "a second install over the first failed:"; sed 's/^/    | /' "$w/err"; }
[ "$("$STEVEDORE" plist get "$w/r/$rel/mavergreen.plist" version 2>/dev/null || :)" = 1.2.4 ] \
  || fail "a second install must replace the first; the manifest still says $("$STEVEDORE" plist get "$w/r/$rel/mavergreen.plist" version 2>/dev/null || :)"
left="$(ls -A "$w/r/opt/mavergreen/.install-products/shipyard")"
[ -z "$left" ] || fail "an install must leave nothing staged beside the prefix; left: $left"

if [ "$(id -u)" -ne 0 ]; then
  mkdir "$w/nr"
  rc=0
  SUDO= sh "$S/install-shipyard-prefix.sh" --root "$w/nr" --version 1.2.3 > "$w/out" 2> "$w/err" || rc=$?
  [ "$rc" -eq 1 ] && grep -q "installing into $w/nr/opt/mavergreen needs root" "$w/err" && [ "$(grep -c . "$w/err")" -eq 1 ] \
    || { fail "with no root and no sudo it must exit 1 in one line naming root; exit $rc:"; sed 's/^/    | /' "$w/err"; }
  [ -z "$(ls -A "$w/nr")" ] && [ ! -s "$w/out" ] || fail "with no root and no sudo it must write nothing"
else
  mkdir "$w/rr"
  sh "$S/install-shipyard-prefix.sh" --root "$w/rr" --version 1.2.3 > /dev/null 2> "$w/err" \
    || { fail "as root the install failed:"; sed 's/^/    | /' "$w/err"; }
  [ "$(find "$w/rr/opt/mavergreen/shipyard" "$w/rr/opt/mavergreen/bin" ! -user 0 | head -1)" = "" ] \
    && [ "$(find "$w/rr/opt/mavergreen/shipyard" ! -group 0 | head -1)" = "" ] \
    || fail "as root the installed prefix and its links must be owned by root"
fi

[ "$fails" -eq 0 ] || { echo "FAIL: $fails case(s) in linux-shipyard-prefix"; exit 1; }
echo "PASS: linux-shipyard-prefix"
