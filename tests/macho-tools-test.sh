#!/bin/sh
# platform: host-agnostic
# spec: scripts/lib/macho-tools.sh -- the Mach-O readers are LLVM's on every host, found next to
#       clang-22, in the family's directories, or by version-suffixed name, and never Apple's.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
LIB="$here/../scripts/lib/macho-tools.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/macho-tools-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
mk() {  # dir name...
  d="$1"; shift; mkdir -p "$d"
  for n in "$@"; do printf '#!/bin/sh\necho %s\n' "$d/$n" > "$d/$n"; chmod +x "$d/$n"; done
}
BASE="/usr/bin:/bin"
resolve() {  # $1 = PATH, $2 = SHIPYARD_MACHO_DIRS, $3 = variable
  env -u OTOOL -u LIPO -u NM -u STRINGS PATH="$1" SHIPYARD_MACHO_DIRS="$2" sh -c ". '$LIB'; mach_tool $3 && eval \"printf '%s\\n' \\\"\\\$$3\\\"\""
}

mk "$w/clangbin" clang-22 llvm-otool llvm-lipo llvm-nm llvm-strings
mk "$w/fam" llvm-otool
got="$(resolve "$w/clangbin:$BASE" "$w/fam" OTOOL)"
[ "$got" = "$w/clangbin/llvm-otool" ] || { echo "FAIL next to clang-22 on PATH wins over the family directory: got $got"; exit 1; }

mk "$w/pathonly" llvm-otool-18 llvm-lipo-18
got="$(resolve "$w/pathonly:$BASE" "$w/fam" OTOOL)"
[ "$got" = "$w/fam/llvm-otool" ] || { echo "FAIL a family directory beats a version-suffixed name on PATH: got $got"; exit 1; }

got="$(resolve "$w/pathonly:$BASE" "" OTOOL)"
[ "$got" = "$w/pathonly/llvm-otool-18" ] || { echo "FAIL a version-suffixed llvm-otool-N on PATH is found: got $got"; exit 1; }
got="$(resolve "$w/pathonly:$BASE" "" LIPO)"
[ "$got" = "$w/pathonly/llvm-lipo-18" ] || { echo "FAIL a version-suffixed llvm-lipo-N on PATH is found: got $got"; exit 1; }

mk "$w/bare" llvm-nm
got="$(resolve "$w/bare:$BASE" "" NM)"
[ "$got" = "$w/bare/llvm-nm" ] || { echo "FAIL an unsuffixed llvm-nm on PATH is found last: got $got"; exit 1; }

mk "$w/apple" otool lipo nm strings
for v in OTOOL LIPO NM STRINGS; do
  rc=0; err="$(resolve "$w/apple:$BASE" "" $v 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { echo "FAIL Apple's tools are never a fallback for $v: got $err"; exit 1; }
  case "$err" in *"set $v to its path"*) ;; *) echo "FAIL the failure should name the variable $v: $err"; exit 1 ;; esac
done

got="$(env OTOOL=/my/otool PATH="$w/clangbin:$BASE" sh -c ". '$LIB'; mach_tool OTOOL && printf '%s\n' \"\$OTOOL\"")"
[ "$got" = /my/otool ] || { echo "FAIL a reader the caller named is kept: got $got"; exit 1; }

rc=0; env PATH="$BASE" sh -c ". '$LIB'; mach_tool FILE" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL an unknown reader is a usage error (2), got $rc"; exit 1; }

echo "PASS: macho-tools"
