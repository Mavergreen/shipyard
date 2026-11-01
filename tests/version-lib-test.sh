#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
V="$here/../scripts/version.sh"
L="$here/../scripts/lib.sh"
SHIPYARD_SCRIPTS="$here/../scripts"; export SHIPYARD_SCRIPTS   # how a consumer repo finds lib/vercmp.sh
w="$(mktemp -d "${TMPDIR:-/tmp}/version-lib-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
mkdir -p "$w/.mavergreen/upstream"
printf '1.26.5\n' > "$w/.mavergreen/upstream/VERSION"
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
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.1' || { echo "FAIL: tags for OTHER upstreams must be ignored -- N resets to 1 when upstream/VERSION moves: $out"; exit 1; }

out="$(MAVERICKS_TAGS='1.26.5-mavericks.rc1' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.1' || { echo "FAIL: a non-numeric suffix is not an N: $out"; exit 1; }

if sh "$V" sideways >/dev/null 2>&1; then echo "FAIL: an unknown mode must be an error, not a silent default"; exit 1; fi

( cd "$w" && git init -q -b main . && git config user.email t@e.com && git config user.name t \
  && git add .mavergreen && git commit -qm base && git tag 1.26.5-mavericks.9 )
out="$(sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.9' || { echo "FAIL: with no MAVERICKS_TAGS it must read the repo's own git tags: $out"; exit 1; }

c="$w/commit"; mkdir -p "$c/.mavergreen/upstream" "$c/.mavergreen/hooks"
printf '0123456789abcdef0123456789abcdef01234567\n# renovate: datasource=git-refs depName=https://example.com/x\n' > "$c/.mavergreen/upstream/COMMIT"
printf '#!/bin/sh\nprintf "20260727\\n"\n' > "$c/.mavergreen/hooks/derive-upstream-version"
out="$(MAVERICKS_ROOT="$c" MAVERICKS_TAGS='20260727-mavericks.2' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=20260727-mavericks.2' \
  || { echo "FAIL: a COMMIT upstream takes its version from hooks/derive-upstream-version: $out"; exit 1; }

p="$w/pin"; mkdir -p "$p/.mavergreen/upstream" "$p/.mavergreen/hooks" "$p/sub"
printf 'v1.5.7@f8745da0123456789abcdef0123456789abcdef0\n' > "$p/.mavergreen/upstream/PIN"
printf '#!/bin/sh\nIFS= read -r r < .mavergreen/upstream/PIN\nr="${r%%%%@*}"\nprintf "%%s\\n" "${r#v}"\n' > "$p/.mavergreen/hooks/derive-upstream-version"
out="$(cd "$p/sub" && MAVERICKS_ROOT="$p" MAVERICKS_TAGS='' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.5.7-mavericks.1' \
  || { echo "FAIL: a PIN upstream takes its version from hooks/derive-upstream-version, run at the repo root: $out"; exit 1; }

rm "$p/.mavergreen/hooks/derive-upstream-version"
if out="$(MAVERICKS_ROOT="$p" MAVERICKS_TAGS='' sh "$V" auto 2>&1)"; then
  echo "FAIL: a PIN upstream with no derive hook must fail, not invent a version: $out"; exit 1
fi
printf '%s\n' "$out" | grep -q 'hooks/derive-upstream-version' || { echo "FAIL: the refusal names the missing hook: $out"; exit 1; }

printf '#!/bin/sh\nexit 0\n' > "$p/.mavergreen/hooks/derive-upstream-version"
if out="$(MAVERICKS_ROOT="$p" MAVERICKS_TAGS='' sh "$V" auto 2>&1)"; then
  echo "FAIL: a derive hook that prints nothing must fail, not yield '-mavericks.1': $out"; exit 1
fi

l="$w/legacy"; mkdir -p "$l"; printf '1.0.0\n' > "$l/UPSTREAM_VERSION"
if out="$(MAVERICKS_ROOT="$l" MAVERICKS_TAGS='' sh "$V" auto 2>&1)"; then
  echo "FAIL: a root UPSTREAM_VERSION is no longer read: $out"; exit 1
fi
printf '%s\n' "$out" | grep -q '.mavergreen/upstream' || { echo "FAIL: the refusal names .mavergreen/upstream/: $out"; exit 1; }

t="$w/two"; mkdir -p "$t/.mavergreen/upstream"; printf '1.0.0\n' > "$t/.mavergreen/upstream/VERSION"; printf 'v1@0123456789abcdef0123456789abcdef01234567\n' > "$t/.mavergreen/upstream/PIN"
if MAVERICKS_ROOT="$t" MAVERICKS_TAGS='' sh "$V" auto >/dev/null 2>&1; then
  echo "FAIL: an upstream with both VERSION and PIN is ambiguous and must fail"; exit 1
fi

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

[ "$(comparison_key 1.0-mavergreen.2)" = 1.0.2 ] || { echo "FAIL key: -mavergreen.N"; exit 1; }
grep -q 'string(REPLACE "-mavergreen\." ' "$here/../MavericksSparkle.cmake" \
  || { echo "FAIL MavericksSparkle.cmake lost its -mavergreen derivation (mirror of comparison_key)"; exit 1; }

vc() { r="$(mavergreen_vercmp "$1" "$2")" && s=0 || s=$?; echo "$s:$r"; }
[ "$(vc 22.1.8-mavericks.5 22.1.8-mavericks.4)" = 0:1 ]   || { echo "FAIL vercmp: .5 > .4"; exit 1; }
[ "$(vc 22.1.8-mavericks.10 22.1.8-mavericks.9)" = 0:1 ]  || { echo "FAIL vercmp: .10 > .9"; exit 1; }
[ "$(vc 20261019.1 20261018.12)" = 0:1 ]                  || { echo "FAIL vercmp: dates"; exit 1; }
[ "$(vc 9.9p2 9.9p1)" = 0:1 ]                             || { echo "FAIL vercmp: pN"; exit 1; }
[ "$(vc 22.1.8-mavergreen.1 22.1.8-mavericks.1)" = 0:0 ]  || { echo "FAIL vercmp: mavergreen == mavericks"; exit 1; }
[ "$(vc 1.0 1.0.0)" = 0:0 ]                               || { echo "FAIL vercmp: trailing zero"; exit 1; }
[ "$(vc 1.0-rc1 1.0)" = 2: ]                              || { echo "FAIL vercmp: -rc1 must be status 2"; exit 1; }
[ "$(vc abc 1)" = 2: ]                                    || { echo "FAIL vercmp: abc must be status 2"; exit 1; }

# spec: scripts/lib.sh -- consumer repos source it with their OWN $SELF (a build/ dir) and SHIPYARD /
#       SHIPYARD_SCRIPTS set from shipyard-scripts; it must find lib/vercmp.sh from those, and fail loudly otherwise.
S="$here/../scripts"
chk() { [ "$(env "$@" sh -c '. "$L" && mavergreen_vercmp 1.0.1 1.0' 2>&1)" = 1 ]; }
L="$S/lib.sh"; export L
chk -u SELF -u SHIPYARD -u SHIPYARD_SCRIPTS SELF="$S"                      || { echo "FAIL lib.sh: shipyard-internal SELF"; exit 1; }
chk -u SELF -u SHIPYARD_SCRIPTS SHIPYARD="$S"                               || { echo "FAIL lib.sh: consumer, SELF unset, SHIPYARD set"; exit 1; }
chk -u SHIPYARD -u SHIPYARD_SCRIPTS SELF="$w" SHIPYARD="$S"                 || { echo "FAIL lib.sh: consumer, unrelated SELF"; exit 1; }
chk -u SELF -u SHIPYARD SHIPYARD_SCRIPTS="$S"                               || { echo "FAIL lib.sh: SHIPYARD_SCRIPTS only"; exit 1; }
err="$(env -u SHIPYARD -u SHIPYARD_SCRIPTS SELF="$w" sh -c '. "$L" && echo reached' 2>&1)" && rc=0 || rc=$?
[ "$err" = "lib.sh: cannot find lib/vercmp.sh beside it; set SHIPYARD_SCRIPTS to shipyard's scripts directory" ] \
  || { echo "FAIL lib.sh: missing vercmp.sh must give exactly the one error line and not continue: $err"; exit 1; }

echo "PASS: version-lib"
