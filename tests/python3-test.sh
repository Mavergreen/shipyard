#!/bin/sh
# platform: host-agnostic
#   usage: python3-test.sh
#          chk_python3 finds a python3 >= 3.9, and fails the python3 check, naming the install
#          command for the host OS, when it finds none. It finds python-315's python3-315 off PATH,
#          as a 10.9 non-login shell has no /opt/mavergreen/bin there. MAVERGREEN_ROOT is the volume to look under.
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
  env -i PATH="$t/bin" SHIPYARD_CHECK_DIR="$here/scripts" MAVERGREEN_ROOT="$t/none" "$@" \
    "$t/bin/sh" -c '. "$SHIPYARD_CHECK_DIR/lib/py.sh"; chk_python3'
}

rc=0; run SHIPYARD_PYTHON3="$t/py38" > "$t/out" 2> "$t/err" || rc=$?
[ "$rc" -ne 0 ] || fail "a python3 reporting 3.8 is refused"
head -1 "$t/err" | grep -q '^python3: ' || fail "the refusal is the python3 check's K2 shape"
grep -q 'fix: ' "$t/err" || fail "the refusal names a fix"

mkdir "$t/bin39"; cp "$t/bin"/* "$t/bin39/"; cp "$t/py39" "$t/bin39/python3"
rc=0; env -i PATH="$t/bin39" SHIPYARD_CHECK_DIR="$here/scripts" MAVERGREEN_ROOT="$t/none" SHIPYARD_PYTHON3="$t/py38" \
  "$t/bin/sh" -c '. "$SHIPYARD_CHECK_DIR/lib/py.sh"; chk_python3' > "$t/out" 2> "$t/err" || rc=$?
[ "$rc" -ne 0 ] || fail "SHIPYARD_PYTHON3 names the interpreter: a 3.8 there is refused even with a 3.9 python3 on PATH"

rc=0; run > "$t/out" 2> "$t/err" || rc=$?
[ "$rc" -ne 0 ] || fail "no python3 at all is refused"
case "$(uname -s)" in
  Darwin) grep -qFx '  fix: /opt/mavergreen/bin/mavergreen install python315' "$t/err" || fail "on macOS the fix names python-315" ;;
  *) grep -qFx '  fix: install python3 >= 3.9' "$t/err" || fail "on Linux the fix names the package install" ;;
esac

run SHIPYARD_PYTHON3="$t/py39" > "$t/out" 2> "$t/err" || fail "a python3 reporting 3.9 is accepted"
[ "$(cat "$t/out")" = "$t/py39" ] || fail "chk_python3 prints the path it chose"

mkdir -p "$t/legacy/usr/local/mavergreen/bin" "$t/vol/opt/mavergreen/bin"
cp "$t/py39" "$t/legacy/usr/local/mavergreen/bin/python3-315"; cp "$t/py39" "$t/vol/opt/mavergreen/bin/python3"
run MAVERGREEN_ROOT="$t/legacy" > "$t/out" 2> "$t/err" || fail "python3-315 under usr/local/mavergreen of MAVERGREEN_ROOT is found off PATH"
[ "$(cat "$t/out")" = "$t/legacy/usr/local/mavergreen/bin/python3-315" ] || fail "chk_python3 prints \$MAVERGREEN_ROOT/usr/local/mavergreen/bin/python3-315"
env -i PATH="$t/bin39" SHIPYARD_CHECK_DIR="$here/scripts" MAVERGREEN_ROOT="$t/legacy" \
  "$t/bin/sh" -c '. "$SHIPYARD_CHECK_DIR/lib/py.sh"; chk_python3' > "$t/out" 2> "$t/err" || fail "a python3 on PATH is accepted"
[ "$(cat "$t/out")" = "$t/legacy/usr/local/mavergreen/bin/python3-315" ] || fail "python3-315 under MAVERGREEN_ROOT comes before PATH"
run MAVERGREEN_ROOT="$t/vol/" > "$t/out" 2> "$t/err" || fail "an /opt python3 under MAVERGREEN_ROOT is accepted"
[ "$(cat "$t/out")" = "$t/vol/opt/mavergreen/bin/python3" ] || fail "the opt/mavergreen python3 under MAVERGREEN_ROOT is found"
mkdir -p "$t/both/opt/mavergreen/bin" "$t/both/usr/local/mavergreen/bin"
cp "$t/py39" "$t/both/opt/mavergreen/bin/python3"; cp "$t/py39" "$t/both/usr/local/mavergreen/bin/python3-315"
run MAVERGREEN_ROOT="$t/both" > "$t/out" 2> "$t/err" || fail "both layouts present is accepted"
[ "$(cat "$t/out")" = "$t/both/opt/mavergreen/bin/python3" ] || fail "opt/mavergreen's python3 comes before usr/local/mavergreen's python3-315"
run MAVERGREEN_ROOT="$t/none" > "$t/out" 2> "$t/err" || :
grep -q "$t/none/opt/mavergreen/bin/python3, $t/none/usr/local/mavergreen/bin/python3-315, and python3-315" "$t/err" || fail "the refusal names exactly the paths it tried"

echo "PASS python3"
