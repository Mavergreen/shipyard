#!/bin/sh
# platform: host-agnostic
#   usage: linux-prerequisites-test.sh
#          scripts/linux-prerequisites.sh against a stub table and a stub apt-get: all present passes,
#          missing ones are installed when it may, and otherwise it fails once naming every missing
#          tool and package. Exit 0 clean, 1 on failure.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; S="$here/../scripts/linux-prerequisites.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/linux-prereq.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
mkdir "$w/bin" "$w/have"
cat > "$w/bin/apt-get" <<STUB
#!/bin/sh
echo "apt-get \$*" >> "$w/apt.log"
[ ! -f "$w/apt-fails" ] || exit 100
[ "\$1" != install ] || for p in "\$@"; do : > "$w/have/\$p"; done
STUB
chmod +x "$w/bin/apt-get"
LINUX_PREREQUISITES="tool-a pkg-a [ -f $w/have/pkg-a ]
tool-b pkg-b [ -f $w/have/pkg-b ]
tool-c pkg-b [ -f $w/have/pkg-b ]"
export LINUX_PREREQUISITES
run() {  # $1 = the script's argument, or ''; the rest = an env prefix
  _a="$1"; shift; rc=0
  env PATH="$w/bin:$PATH" "$@" sh "$S" ${_a:+"$_a"} > "$w/out" 2> "$w/err" || rc=$?
}

: > "$w/have/pkg-a"
run --check env
[ "$rc" -eq 1 ] || fail "--check with tools missing must exit 1; got $rc"
[ "$(grep -c . "$w/err")" -eq 1 ] && grep -qF "missing tool-b, tool-c, and --check installs nothing: install the packages pkg-b first" "$w/err" \
  || fail "--check must name every missing tool and its package in one line; got: $(cat "$w/err")"
[ ! -f "$w/apt.log" ] || fail "--check must not run apt-get"

if [ "$(id -u)" -ne 0 ]; then
  run "" env SUDO=
  [ "$rc" -eq 1 ] && grep -qF "missing tool-b, tool-c, and this user is not root and has no working sudo -n" "$w/err" \
    || fail "with no root or sudo it must fail naming what is missing; got $rc: $(cat "$w/err")"
  [ ! -f "$w/apt.log" ] || fail "with no root or sudo it must not run apt-get"
fi

: > "$w/apt-fails"
run "" env SUDO=env
[ "$rc" -eq 1 ] && grep -qF "apt-get install pkg-b failed" "$w/err" || fail "a failing apt-get must fail naming it; got $rc: $(cat "$w/err")"
rm -f "$w/apt-fails" "$w/apt.log"

run "" env SUDO=env
[ "$rc" -eq 0 ] || fail "with sudo and apt-get it must install what is missing and pass; got $rc: $(cat "$w/err")"
grep -qx "apt-get install -y -qq --no-install-recommends pkg-b" "$w/apt.log" 2>/dev/null \
  || fail "it must install each missing package once, and only those; apt-get saw: $(cat "$w/apt.log" 2>/dev/null)"

rm -f "$w/apt.log"
run "" env
[ "$rc" -eq 0 ] && [ ! -f "$w/apt.log" ] || fail "with everything present it must pass and install nothing; got $rc"

[ "$fails" -eq 0 ] || { echo "FAIL: $fails case(s) in linux-prerequisites"; exit 1; }
echo "PASS: linux-prerequisites"
