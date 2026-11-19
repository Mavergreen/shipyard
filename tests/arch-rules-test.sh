#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../scripts/lib/vercmp.sh"
. "$here/../scripts/lib/arch-rules.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/arch-rules-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $*"; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }
derive() { printf '%s' "$1" | arch_derive 2>"$w/err" | tr '\n' '/' ; }
derive_status() { printf '%s' "$1" | arch_derive >/dev/null 2>"$w/err" && echo 0 || echo $?; }

eq "empty" "$(derive '')" "class neutral/arm64-floor none/"
eq "x86_64" "$(derive 'bin/a x86_64 10.9
')" "class x86_64/arm64-floor none/"
eq "12.10 beats 12.9" "$(derive 'bin/a x86_64 10.9
bin/a arm64 12.9
bin/b x86_64 10.9
bin/b arm64 12.10
')" "class universal/arm64-floor 12.10/"
eq "13 is written 13.0" "$(derive 'bin/a x86_64 10.9
bin/a arm64 13
')" "class universal/arm64-floor 13.0/"
eq "13 beats 12.3" "$(derive 'bin/a x86_64 10.9
bin/a arm64 12.3
bin/b x86_64 10.9
bin/b arm64 13
')" "class universal/arm64-floor 13.0/"
eq "arm64e counts" "$(derive 'bin/a x86_64 10.9
bin/a arm64e 11.0
')" "class universal/arm64-floor 11.0/"
eq "no minos status" "$(derive_status 'bin/a x86_64 10.9
bin/a arm64 -
')" 1
grep -q 'bin/a: arm64 slice records no minimum OS, so the arm64 floor cannot be derived' "$w/err" || fail "no minos message: $(cat "$w/err")"
eq "unknown minos status" "$(derive_status 'bin/a x86_64 10.9
bin/a arm64 ?
')" 1
eq "arm64 only status" "$(derive_status 'bin/a x86_64 10.9
bin/b arm64 13.0
')" 1
grep -q 'bin/b is arm64 only; a host binary carries x86_64, and arm64 only beside it' "$w/err" || fail "arm64 only message: $(cat "$w/err")"

eq "neutral" "$(arch_rule neutral no 10.9.5 none)" none
eq "neutral newer" "$(arch_rule neutral yes 10.9.5 none)" none
eq "x86_64" "$(arch_rule x86_64 no 10.9.5 none)" intel
eq "x86_64 newer" "$(arch_rule x86_64 yes 10.9.5 none)" intel-newer
eq "universal" "$(arch_rule universal yes 10.9.5 13.0)" "arm64-below 13.0"
eq "universal without newer-macos" "$(arch_rule universal no 10.9.5 13.0 2>/dev/null && echo 0 || echo $?)" 1
eq "distribution refuses it too" "$(arch_distribution universal no 10.9.5 13.0 >/dev/null 2>&1 && echo 0 || echo $?)" 1

d="$(arch_distribution x86_64 no 10.9.5 none)"
printf '%s\n' "$d" | grep -qx '<allowed-os-versions><os-version min="10.9.5" before="10.11"/></allowed-os-versions>' || fail "x86_64 allowed-os-versions: $d"
printf '%s\n' "$d" | grep -qx '<installation-check script="mavergreen_arch()"/>' || fail "x86_64 installation-check"
printf '%s\n' "$d" | grep -Fqx '<script><![CDATA[' || fail "script open"
printf '%s\n' "$d" | grep -Fqx ']]></script>' || fail "script close"
printf '%s\n' "$d" | grep -q "system.sysctl('hw.optional.arm64') == 1" || fail "intel condition"
printf '%s\n' "$d" | grep -q "This package is built for Intel Macs running Mac OS X 10.9 or 10.10." || fail "intel message"
printf '%s\n' "$d" | grep -q "^[[:space:]]" && fail "a line starts with a blank"
printf '%s\n' "$d" | grep -q 'hostArchitectures' && fail "options belong to set_install_floor"

d="$(arch_distribution x86_64 yes 10.9.5 none)"
printf '%s\n' "$d" | grep -qx '<allowed-os-versions><os-version min="10.9.5"/></allowed-os-versions>' || fail "newer-macos drops before: $d"
printf '%s\n' "$d" | grep -q "my.result.message = 'This package is built for Intel Macs.';" || fail "intel-newer message"
d="$(arch_distribution neutral no 10.9.5 none)"
eq "neutral is one line" "$d" '<allowed-os-versions><os-version min="10.9.5" before="10.11"/></allowed-os-versions>'
d="$(arch_distribution neutral yes 10.9.5 none)"
eq "neutral newer is one line" "$d" '<allowed-os-versions><os-version min="10.9.5"/></allowed-os-versions>'
d="$(arch_distribution universal yes 10.9.5 13.0)"
printf '%s\n' "$d" | grep -qx '<allowed-os-versions><os-version min="10.9.5"/></allowed-os-versions>' || fail "universal has no before"
printf '%s\n' "$d" | grep -q "system.sysctl('hw.optional.arm64') == 1 && system.compareVersions(system.version.ProductVersion, '13.0') < 0" || fail "arm64-below condition"
printf '%s\n' "$d" | grep -q "my.result.title = 'Needs a newer macOS';" || fail "arm64-below title"
printf '%s\n' "$d" | grep -q "On Apple Silicon this package needs macOS 13.0 or later." || fail "arm64-below message"
printf '%s\n' "$d" | grep -q "^[[:space:]]" && fail "universal: a line starts with a blank"
printf '%s\n' "$d" | grep -q "my.result.type = 'Fatal';" || fail "Fatal"

eq "requires: default" "$(arch_requires_line x86_64 no 10.9.5 none)" "Mac OS X 10.9.5 through 10.10"
eq "requires: neutral default" "$(arch_requires_line neutral no 10.9.5 none)" "Mac OS X 10.9.5 through 10.10"
eq "requires: x86_64 newer" "$(arch_requires_line x86_64 yes 10.9.5 none)" "an Intel Mac with Mac OS X 10.9.5 or later"
eq "requires: neutral newer" "$(arch_requires_line neutral yes 10.9.5 none)" "Mac OS X 10.9.5 or later"
eq "requires: universal" "$(arch_requires_line universal yes 10.9.5 13.0)" "Mac OS X 10.9.5 or later; on Apple Silicon, macOS 13.0 or later"

g="$w/target"
printf 'lib/clang/22/lib/darwin/*\nlib/x\n\nlib/My*\n' > "$g"
arch_is_target lib/clang/22/lib/darwin/x/libclang_rt.osx.a "$g" || fail "glob star spans /"
arch_is_target lib/x "$g" || fail "exact line"
arch_is_target lib/xy "$g" && fail "lib/x must not match lib/xy"
arch_is_target "lib/My Lib.dylib" "$g" || fail "a path with a space"
arch_is_target bin/other "$g" && fail "unrelated path"
printf 'lib/z' > "$g"
arch_is_target lib/z "$g" || fail "last line with no newline"

arch_is_exempt "Library/Application Support/Mavergreen/w-updater.app/Contents/MacOS/w" || fail "updater is exempt"
arch_is_exempt "Applications/Mavergreen/W.app/Contents/MacOS/w" && fail "the app is not exempt"
echo "PASS: arch-rules"
