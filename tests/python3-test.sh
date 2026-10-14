#!/bin/sh
# platform: host-agnostic
#   usage: python3-test.sh
#          chk_python3 finds a python3 >= 3.9, and fails the python3 check, naming the install
#          command for the host OS, when it finds none.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/python3-test.XXXXXX")"
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL $1"; exit 1; }

mkdir "$t/bin"
for tool in sh uname cut grep cat; do
  ln -s "$(command -v $tool)" "$t/bin/$tool"
done
printf '#!/bin/sh\nexit 1\n' > "$t/py38"
printf '#!/bin/sh\nexit 0\n' > "$t/py39"
chmod +x "$t/py38" "$t/py39"

run() {
  env -i PATH="$t/bin" SHIPYARD_CHECK_DIR="$here/scripts" SHIPYARD_OPT_PREFIX="$t/none" "$@" \
    "$t/bin/sh" -c '. "$SHIPYARD_CHECK_DIR/lib/py.sh"; chk_python3'
}

rc=0; run SHIPYARD_PYTHON3="$t/py38" > "$t/out" 2> "$t/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a python3 reporting 3.8 is refused"
head -1 "$t/err" | grep -q '^python3: ' || fail "the refusal is the python3 check's K2 shape"
grep -q 'fix: ' "$t/err" || fail "the refusal names a fix"

rc=0; run > "$t/out" 2> "$t/err" || rc=$?
[ "$rc" -ne 0 ] || fail "no python3 at all is refused"
case "$(uname -s)" in
  Darwin) grep -q 'python-315' "$t/err" || fail "on macOS the fix names python-315" ;;
  *) grep -q 'apt-get install python3' "$t/err" || fail "on Linux the fix names the package install" ;;
esac

run SHIPYARD_PYTHON3="$t/py39" > "$t/out" 2> "$t/err" || fail "a python3 reporting 3.9 is accepted"
[ "$(cat "$t/out")" = "$t/py39" ] || fail "chk_python3 prints the path it chose"

echo "PASS python3"
