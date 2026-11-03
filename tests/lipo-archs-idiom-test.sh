#!/bin/sh
# platform: host-agnostic
# spec: check-family-conventions.sh check 10's `lipo -archs` replacement advice must actually be
#       equivalent, on BOTH the platform that lacks -archs (10.9) and the platform CI runs on
#       (Tahoe) -- asserting the rule's advice, not the rule, since a lint that names a fix
#       nobody verified is how the next 10.9 gap gets introduced by the fix for the last one.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
CL="$(sh "$here/../scripts/fetch_clang22.sh" "$here/..")"
w="$(mktemp -d "${TMPDIR:-/tmp}/lipo-idiom.XXXXXX")"; trap 'rm -rf "$w"' EXIT
cc() { "$CL/bin/clang" --no-default-config -Wno-unused-command-line-argument -target x86_64-apple-macos10.9 -isysroot "$(sh "$here/../scripts/fetch_sdk.sh")" -fuse-ld=lld "$@"; }

# platform: lipo -info's output takes two different spellings depending on whether the input is
#           fat ("Architectures in the fat file: X are: a b") or thin ("Non-fat file: X is
#           architecture: a"); the idiom must handle both.
bin="$w/hello"
printf 'int main(void){return 0;}\n' | cc -x c - -o "$bin"

# platform: 10.9's lipo, given a static ARCHIVE (the case mavericks-golang hits checking
#           libMacportsLegacySupport.a, and the case that broke the first version of this
#           advice), prints "input file X is not a fat file" to STDOUT *before* the real line
#           ("input file /tmp/liba.a is not a fat file" then
#           "Non-fat file: /tmp/liba.a is architecture: x86_64"). A plain s/.*: // passes that
#           first line straight through, so an exact comparison sees "input file ... is not a
#           fat file x86_64" and fails; sed -n ...p prints only lines that matched. A thin
#           EXECUTABLE does not reproduce this (one clean line), which is precisely why testing
#           one alone would have missed the bug.
printf 'int f(void){return 0;}\n' | cc -x c -c -o "$w/f.o" -
"$CL/bin/llvm-ar" rcs "$w/libf.a" "$w/f.o"
pass() {  # $1 = the lipo to read with  $2 = what to call it
  lipo="$1"
  a="$("$lipo" -info "$w/libf.a" 2>/dev/null | sed -n 's/.*: //p' | xargs)"
  [ "$a" = x86_64 ] || { echo "FAIL: $2: static archive gave '$a', expected exactly 'x86_64'"; exit 1; }

  idiom="$("$lipo" -info "$bin" 2>/dev/null | sed -n 's/.*: //p')"
  [ -n "$idiom" ] || { echo "FAIL: $2: -info idiom produced nothing for $bin"; exit 1; }
  case "$idiom" in
    *x86_64*|*arm64*|*i386*) : ;;
    *) echo "FAIL: $2: -info idiom gave '$idiom', which names no architecture"; exit 1 ;;
  esac

  if "$lipo" -archs "$bin" >/dev/null 2>&1; then   # portability-ok: this test exists to compare against -archs where it exists
    archs="$("$lipo" -archs "$bin" 2>/dev/null)"   # portability-ok: this test exists to compare against -archs where it exists
    norm() { tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' '; }
    a="$(printf '%s' "$idiom" | norm)"; b="$(printf '%s' "$archs" | norm)"
    [ "$a" = "$b" ] || { echo "FAIL: $2: idiom '$a' != lipo -archs '$b' -- compared as SETS since -info separates with spaces and can leave a trailing one, -archs need not agree on order or padding, and neither promises a stable sequence"; exit 1; }   # portability-ok: this test exists to compare against -archs where it exists
    echo "PASS: lipo-archs-idiom ($2; -archs present; idiom matches: $a)"
  else
    echo "PASS: lipo-archs-idiom ($2; no -archs here, as on 10.9; idiom yields: $idiom)"   # portability-ok: this test exists to compare against -archs where it exists
  fi
}
pass "$CL/bin/llvm-lipo" llvm-lipo
# platform: the system lipo is the one whose spellings the idiom exists for (10.9's has no -archs); a
#           10.9 box without the Command Line Tools has only a stub at /usr/bin/lipo, and Linux has none.
# platform: guarded macOS-only call -- -x /usr/bin/lipo is false on Linux
if [ -x /usr/bin/lipo ] && /usr/bin/lipo -info "$bin" >/dev/null 2>&1; then
  pass /usr/bin/lipo "system lipo"
fi
