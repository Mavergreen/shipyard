#!/bin/sh
# platform: host-agnostic
#   usage: objc-reference-dir-test.sh
# spec: scripts/objc-reference-dir.sh header -- an installed shipyard (scripts/ beside reference/objc/) answers with
#       its own staged reference set; a checkout, which stages none, answers with the pinned Drydock's
#       share/drydock/objc/reference, here a fixture prefix named by MAVERGREEN_DRYDOCK_PREFIX. Nothing is fetched.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/objc-reference-dir-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
T=$(cd "$T" && pwd -P)
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [ ! -f "$T/err" ] || sed 's/^/    | /' "$T/err"; fails=$((fails + 1)); }
unset MAVERGREEN_DRYDOCK_PREFIX
# spec: scripts/objc-reference-dir.sh header -- stage DIR: the scripts it runs, copied to DIR/scripts as an install lays them out.
stage() {
  mkdir -p "$1/scripts" "$1/.mavergreen/ingredients/drydock"
  for s in objc-reference-dir.sh fetch_drydock.sh; do cp "$ROOT/scripts/$s" "$1/scripts/" 2>/dev/null || :; done
  printf 'v9.9.9\n' >"$1/.mavergreen/ingredients/drydock/VERSION"
}
run() { rc=0; out=$(sh "$1/scripts/objc-reference-dir.sh" 2>"$T/err") || rc=$?; }

stage "$T/inst"; mkdir -p "$T/inst/reference/objc"
run "$T/inst"
[ "$rc" = 0 ] && [ "$out" = "$T/inst/reference/objc" ] && pass 'an installed shipyard answers with its own reference/objc' ||
  fail "installed layout: exit $rc, printed '$out', want $T/inst/reference/objc"

stage "$T/co"
mkdir -p "$T/drydock/bin" "$T/drydock/share/drydock/objc/reference"
printf '#!/bin/sh\nexit 0\n' >"$T/drydock/bin/drydock-objc"; chmod +x "$T/drydock/bin/drydock-objc"
MAVERGREEN_DRYDOCK_PREFIX="$T/drydock"; export MAVERGREEN_DRYDOCK_PREFIX
run "$T/co"
[ "$rc" = 0 ] && [ "$out" = "$T/drydock/share/drydock/objc/reference" ] &&
  pass "a checkout answers with the pinned Drydock's share/drydock/objc/reference" ||
  fail "checkout: exit $rc, printed '$out', want $T/drydock/share/drydock/objc/reference"

rmdir "$T/drydock/share/drydock/objc/reference"
run "$T/co"
[ "$rc" = 1 ] && [ -z "$out" ] && pass 'a Drydock with no reference set is a failure, not an empty answer' ||
  fail "a Drydock with no reference set: exit $rc, printed '$out', want 1 and nothing"

MAVERGREEN_DRYDOCK_PREFIX="$T/no-such-drydock"
run "$T/co"
[ "$rc" = 1 ] && [ -z "$out" ] && pass 'a Drydock that cannot be had is a failure' ||
  fail "no Drydock: exit $rc, printed '$out', want 1 and nothing"

[ "$fails" = 0 ] && echo 'objc-reference-dir-test: all passed' || { echo "objc-reference-dir-test: $fails failed"; exit 1; }
