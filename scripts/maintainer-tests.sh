#!/bin/sh
# platform: host-agnostic
#   usage: maintainer-tests.sh BOX
#          Runs every tests/maintainer-tests line for BOX (10.9 or golden-gate), one after another,
#          with SHIPYARD_ON_TARGET=1, and prints PASS, FAIL or SKIP (exit 77) for each, with a failed
#          test's output. Exit 1 if any failed, 2 on a usage error or a BOX with no lines.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: maintainer-tests.sh BOX" >&2; exit 2; }
box=$1
cd "$root"
list="$(awk -v b="$box" '$1 == b { print $2 }' tests/maintainer-tests)"
[ -n "$list" ] || { echo "maintainer-tests: tests/maintainer-tests has no lines for '$box'" >&2; exit 2; }
SHIPYARD_ON_TARGET=1; export SHIPYARD_ON_TARGET
log="$(mktemp "${TMPDIR:-/tmp}/maintainer-tests.XXXXXX")"; trap 'rm -f "$log"' EXIT
pass=0; fail=0; skip=0
for t in $list; do
  case "$t" in *.bats) set -- bats "$t" ;; *) set -- sh "$t" ;; esac
  rc=0; "$@" > "$log" 2>&1 < /dev/null || rc=$?
  case "$rc" in
    0) echo "PASS $t"; pass=$((pass + 1)) ;;
    77) echo "SKIP $t ($(tail -1 "$log"))"; skip=$((skip + 1)) ;;
    *) echo "FAIL $t (exit $rc)"; sed 's/^/    | /' "$log"; fail=$((fail + 1)) ;;
  esac
done
echo "maintainer-tests $box: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ]
