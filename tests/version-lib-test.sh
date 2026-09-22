#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
V="$here/../scripts/version.sh"
L="$here/../scripts/lib.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/version-lib-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
printf '1.26.5\n' > "$w/UPSTREAM_VERSION"
export MAVERICKS_ROOT="$w"

got="$(. "$L"; upstream_version)"
[ "$got" = 1.26.5 ] || { echo "FAIL upstream_version: '$got'"; exit 1; }

out="$(MAVERICKS_TAGS='' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.1' || { echo "FAIL: a new upstream with no tags yet must be release number 1, and release: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'TAG=1.26.5-mavericks.1'  || { echo "FAIL auto/new TAG: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'RELEASE=yes'             || { echo "FAIL auto/new REL: $out"; exit 1; }

out="$(MAVERICKS_TAGS='1.26.5-mavericks.1
1.26.5-mavericks.3
1.26.5-mavericks.2' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.3' || { echo "FAIL: auto for an already-released upstream must report the current N: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'RELEASE=no'              || { echo "FAIL: auto for an already-released upstream must NOT release again: $out"; exit 1; }

out="$(MAVERICKS_TAGS='1.26.5-mavericks.3' sh "$V" local)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.4' || { echo "FAIL: local must report the next N: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'RELEASE=yes'             || { echo "FAIL: local must release: $out"; exit 1; }

out="$(MAVERICKS_TAGS='1.26.4-mavericks.7' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.1' || { echo "FAIL: tags for OTHER upstreams must be ignored -- N resets to 1 when UPSTREAM_VERSION moves: $out"; exit 1; }

out="$(MAVERICKS_TAGS='1.26.5-mavericks.rc1' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.1' || { echo "FAIL: a non-numeric suffix is not an N: $out"; exit 1; }

if sh "$V" sideways >/dev/null 2>&1; then echo "FAIL: an unknown mode must be an error, not a silent default"; exit 1; fi

( cd "$w" && git init -q -b main . && git config user.email t@e.com && git config user.name t \
  && git add UPSTREAM_VERSION && git commit -qm base && git tag 1.26.5-mavericks.9 )
out="$(sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.9' || { echo "FAIL: with no MAVERICKS_TAGS it must read the repo's own git tags: $out"; exit 1; }

mkdir -p "$w/lines/127"
printf '1.27.0\n' > "$w/lines/127/UPSTREAM_VERSION"
out="$(MAVERICKS_UPSTREAM_FILE="$w/lines/127/UPSTREAM_VERSION" MAVERICKS_TAGS='' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.27.0-mavericks.1' \
  || { echo "FAIL: a repo whose upstream isn't at the fixed UPSTREAM_VERSION path (container-tools, tailscale: components/<name>/version) needs the file to be an input rather than a fixed path: $out"; exit 1; }
out="$(MAVERICKS_UPSTREAM_FILE="$w/lines/127/UPSTREAM_VERSION" MAVERICKS_TAGS='1.26.5-mavericks.9' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.27.0-mavericks.1' || { echo "FAIL: tags from the OTHER line must not affect this one's N: $out"; exit 1; }

# spec: SKILL.md "Release notes" -- comparison_key() is the ONE Sparkle-comparable-version
#       derivation; its absence from previous-release-tag.sh is why no openssh release ever
#       found its baseline, when gen_appcast.sh's own copy learned the "pN" rule and
#       previous-release-tag.sh's didn't.
. "$here/../scripts/lib.sh"
[ "$(comparison_key 1.102.0-mavericks.4)" = 1.102.0.4 ] || { echo "FAIL key: -mavericks.N"; exit 1; }
[ "$(comparison_key 9.9p2-mavericks.3)"   = 9.9.2.3 ]   || { echo "FAIL key: pN + N"; exit 1; }
[ "$(comparison_key 9.9p2)"               = 9.9.2 ]     || { echo "FAIL key: bare pN"; exit 1; }
[ "$(comparison_key 20260727-mavericks.2)" = 20260727.2 ] || { echo "FAIL key: date"; exit 1; }
[ "$(comparison_key 1.26.8)"              = 1.26.8 ]    || { echo "FAIL key: plain semver"; exit 1; }
numeric "$(comparison_key 9.9p2-mavericks.3)" || { echo "FAIL key: pN result must be orderable"; exit 1; }

grep -q 'string(REPLACE "-mavericks' "$here/../MavericksSparkle.cmake" \
  || { echo "FAIL: MavericksSparkle.cmake is a deliberate mirror of comparison_key() (a .cmake file cannot source lib.sh) and must stay identical, so a change here must fail HERE rather than as \"the updater thinks it is current\" -- lost its -mavericks derivation"; exit 1; }
grep -q '(\[0-9\])p(\[0-9\])' "$here/../MavericksSparkle.cmake" \
  || { echo "FAIL MavericksSparkle.cmake lost its pN derivation"; exit 1; }

grep -q 's/-mavericks\\./\\./' "$here/../scripts/gen_appcast.sh" 2>/dev/null \
  && { echo "FAIL: gen_appcast.sh must NOT carry its own derivation, only call comparison_key() -- this is a regression test for the family's ONE-derivation rule violated when the pN rule was added to gen_appcast but not to previous-release-tag"; exit 1; }

echo "PASS: version-lib"
