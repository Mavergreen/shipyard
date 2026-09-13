#!/bin/sh
# spec: check-family-conventions.sh check 10's `lipo -archs` replacement advice must actually be
#       equivalent, on BOTH the platform that lacks -archs (10.9) and the platform CI runs on
#       (Tahoe) -- asserting the rule's advice, not the rule, since a lint that names a fix
#       nobody verified is how the next 10.9 gap gets introduced by the fix for the last one.
set -eu
command -v lipo >/dev/null 2>&1 || { echo "no lipo -- skipping"; exit 77; }

# platform: lipo -info's output takes two different spellings depending on whether the input is
#           fat ("Architectures in the fat file: X are: a b") or thin ("Non-fat file: X is
#           architecture: a"); the idiom must handle both.
bin=/bin/sh
[ -x "$bin" ] || { echo "no $bin -- skipping"; exit 77; }

# platform: 10.9's lipo, given a static ARCHIVE (the case mavericks-golang hits checking
#           libMacportsLegacySupport.a, and the case that broke the first version of this
#           advice), prints "input file X is not a fat file" to STDOUT *before* the real line
#           ("input file /tmp/liba.a is not a fat file" then
#           "Non-fat file: /tmp/liba.a is architecture: x86_64"). A plain s/.*: // passes that
#           first line straight through, so an exact comparison sees "input file ... is not a
#           fat file x86_64" and fails; sed -n ...p prints only lines that matched. A thin
#           EXECUTABLE does not reproduce this (one clean line), which is precisely why testing
#           one alone would have missed the bug.
w="$(mktemp -d "${TMPDIR:-/tmp}/lipo-idiom.XXXXXX")"
if printf 'int f(void){return 0;}\n' | cc -arch x86_64 -x c -c -o "$w/f.o" - 2>/dev/null &&
   ar rcs "$w/libf.a" "$w/f.o" 2>/dev/null; then
  a="$(lipo -info "$w/libf.a" 2>/dev/null | sed -n 's/.*: //p' | xargs)"
  [ "$a" = x86_64 ] || { echo "FAIL: static archive gave '$a', expected exactly 'x86_64'"; rm -rf "$w"; exit 1; }
fi
rm -rf "$w"

idiom="$(lipo -info "$bin" 2>/dev/null | sed -n 's/.*: //p')"
[ -n "$idiom" ] || { echo "FAIL: -info idiom produced nothing for $bin"; exit 1; }
case "$idiom" in
  *x86_64*|*arm64*|*i386*) : ;;
  *) echo "FAIL: -info idiom gave '$idiom', which names no architecture"; exit 1 ;;
esac

if lipo -archs "$bin" >/dev/null 2>&1; then   # portability-ok: this test exists to compare against -archs where it exists
  archs="$(lipo -archs "$bin" 2>/dev/null)"   # portability-ok: this test exists to compare against -archs where it exists
  norm() { tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' '; }
  a="$(printf '%s' "$idiom" | norm)"; b="$(printf '%s' "$archs" | norm)"
  [ "$a" = "$b" ] || { echo "FAIL: idiom '$a' != lipo -archs '$b' -- compared as SETS since -info separates with spaces and can leave a trailing one, -archs need not agree on order or padding, and neither promises a stable sequence"; exit 1; }   # portability-ok: this test exists to compare against -archs where it exists
  echo "PASS: lipo-archs-idiom (-archs present; idiom matches: $a)"
else
  echo "PASS: lipo-archs-idiom (no -archs here, as on 10.9; idiom yields: $idiom)"   # portability-ok: this test exists to compare against -archs where it exists
fi
