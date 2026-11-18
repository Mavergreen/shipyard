#!/bin/sh
# platform: host-agnostic
# spec: scripts/mavergreen-meta.sh mavergreen_prefix -- /opt/mavergreen, or /opt/mavergreen/SHORT for a name lib/name-rules.sh
#       accepts; status 2 and nothing on stdout for any other; MavergreenPrefix.cmake runs that function and derives nothing itself.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
w="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-prefix-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
. "$root/scripts/mavergreen-meta.sh"
. "$root/scripts/lib/name-rules.sh"

[ "$(mavergreen_prefix)" = /opt/mavergreen ] || fail "mavergreen_prefix prints /opt/mavergreen"
[ "$(mavergreen_prefix go127)" = /opt/mavergreen/go127 ] || fail "mavergreen_prefix go127 prints /opt/mavergreen/go127"
for bad in Go127 var mavergreen ''; do
  rc=0; out="$(mavergreen_prefix "$bad" 2>/dev/null)" || rc=$?
  [ "$rc" = 2 ] || fail "mavergreen_prefix '$bad' exits 2, got $rc"
  [ -z "$out" ] || fail "mavergreen_prefix '$bad' prints nothing, got $out"
done

rc=0; out="$(sh -c '. "$1/scripts/mavergreen-meta.sh"; mavergreen_prefix go127' sh "$root" 2>"$w/err")" || rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] || fail "without lib/name-rules.sh sourced, mavergreen_prefix SHORT exits 2 and prints nothing"
grep -q mavergreen_name_ok "$w/err" || fail "without lib/name-rules.sh sourced, mavergreen_prefix names the missing mavergreen_name_ok"

cat > "$w/ok.cmake" <<CM
include("$root/MavergreenPrefix.cmake")
mavergreen_prefix(P shipyard)
message("P=\${P}")
mavergreen_prefix(Q)
message("Q=\${Q}")
CM
cmake -P "$w/ok.cmake" > "$w/ok.log" 2>&1 || fail "mavergreen_prefix(P shipyard) in cmake -P: $(cat "$w/ok.log")"
grep -q '^P=/opt/mavergreen/shipyard$' "$w/ok.log" || fail "cmake prints P=/opt/mavergreen/shipyard: $(cat "$w/ok.log")"
grep -q '^Q=/opt/mavergreen$' "$w/ok.log" || fail "cmake prints Q=/opt/mavergreen: $(cat "$w/ok.log")"

cat > "$w/bad.cmake" <<CM
include("$root/MavergreenPrefix.cmake")
mavergreen_prefix(P Bad)
CM
rc=0; cmake -P "$w/bad.cmake" > "$w/bad.log" 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "mavergreen_prefix(P Bad) fails the configure"
grep -q 'Bad' "$w/bad.log" || fail "the failure names Bad: $(cat "$w/bad.log")"
echo "PASS: mavergreen-prefix"
