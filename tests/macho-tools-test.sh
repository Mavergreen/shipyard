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
resolve() {  # $1 = PATH, $2 = SHIPYARD_MACHO_DIRS, $3 = variable
  env -u OTOOL -u LIPO -u NM -u STRINGS PATH="$1" SHIPYARD_MACHO_DIRS="$2" /bin/sh -c ". '$LIB'; mach_tool $3 && eval \"printf '%s\\n' \\\"\\\$$3\\\"\""
}

mk "$w/clangbin" clang-22 llvm-otool llvm-lipo llvm-nm llvm-strings
mk "$w/fam" llvm-otool
got="$(resolve "$w/clangbin" "$w/fam" OTOOL)"
[ "$got" = "$w/clangbin/llvm-otool" ] || { echo "FAIL next to clang-22 on PATH wins over the family directory: got $got"; exit 1; }

mk "$w/pathonly" llvm-otool-18 llvm-lipo-18
got="$(resolve "$w/pathonly" "$w/fam" OTOOL)"
[ "$got" = "$w/fam/llvm-otool" ] || { echo "FAIL a family directory beats a version-suffixed name on PATH: got $got"; exit 1; }

got="$(resolve "$w/pathonly" "" OTOOL)"
[ "$got" = "$w/pathonly/llvm-otool-18" ] || { echo "FAIL a version-suffixed llvm-otool-N on PATH is found: got $got"; exit 1; }
got="$(resolve "$w/pathonly" "" LIPO)"
[ "$got" = "$w/pathonly/llvm-lipo-18" ] || { echo "FAIL a version-suffixed llvm-lipo-N on PATH is found: got $got"; exit 1; }

mk "$w/bare" llvm-nm
got="$(resolve "$w/bare" "" NM)"
[ "$got" = "$w/bare/llvm-nm" ] || { echo "FAIL an unsuffixed llvm-nm on PATH is found last: got $got"; exit 1; }

mk "$w/apple" otool lipo nm strings
for v in OTOOL LIPO STRINGS; do
  rc=0; err="$(resolve "$w/apple" "" $v 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { echo "FAIL Apple's tools are never a fallback for $v: got $err"; exit 1; }
  case "$err" in *"set $v to its path"*) ;; *) echo "FAIL the failure should name the variable $v: $err"; exit 1 ;; esac
done

# spec: scripts/lib/macho-tools.sh -- NM resolves as the retired separate nm reader did: an explicit NM, else the
#       llvm-nm beside the llvm-otool or llvm-lipo the caller chose, else an installed clang22's or
#       clang22-cross's (SHIPYARD_MG_PREFIX, default /usr/local/mavergreen), else a bare nm.
nm_resolve() {  # $1 = env assignments, run with OTOOL LIPO NM unset and nothing on PATH but stubs
  env -u OTOOL -u LIPO -u NM -u STRINGS PATH="$w/apple" SHIPYARD_MACHO_DIRS="" "$@" /bin/sh -c ". '$LIB'; mach_tool NM && printf '%s\n' \"\$NM\""
}
mk "$w/llvm/bin" llvm-nm llvm-otool llvm-lipo
mk "$w/empty" keep
got="$(env -u OTOOL -u LIPO PATH="$w/apple" NM=/my/nm OTOOL="$w/llvm/bin/llvm-otool" /bin/sh -c ". '$LIB'; mach_tool NM && printf '%s\n' \"\$NM\"")"
[ "$got" = /my/nm ] || { echo "FAIL an explicit NM wins: got $got"; exit 1; }
got="$(nm_resolve OTOOL="$w/llvm/bin/llvm-otool" SHIPYARD_MG_PREFIX="$w/empty")"
[ "$got" = "$w/llvm/bin/llvm-nm" ] || { echo "FAIL NM unset: the llvm-nm beside OTOOL's llvm-otool: got $got"; exit 1; }
got="$(nm_resolve LIPO="$w/llvm/bin/llvm-lipo" SHIPYARD_MG_PREFIX="$w/empty")"
[ "$got" = "$w/llvm/bin/llvm-nm" ] || { echo "FAIL NM unset: the llvm-nm beside LIPO's llvm-lipo: got $got"; exit 1; }
mk "$w/mg/clang22/bin" llvm-nm
got="$(env -u OTOOL -u LIPO -u NM PATH="$w/apple" SHIPYARD_MACHO_DIRS= SHIPYARD_MG_PREFIX="$w/mg" /bin/sh -c ". '$LIB'; mach_tool NM && printf '%s\n' \"\$NM\"")"
[ "$got" = "$w/mg/clang22/bin/llvm-nm" ] || { echo "FAIL NM unset, no llvm readers chosen: an installed clang22's llvm-nm: got $got"; exit 1; }
mk "$w/mgx/clang22-cross/bin" llvm-nm
got="$(env -u OTOOL -u LIPO -u NM PATH="$w/apple" SHIPYARD_MACHO_DIRS= SHIPYARD_MG_PREFIX="$w/mgx" /bin/sh -c ". '$LIB'; mach_tool NM && printf '%s\n' \"\$NM\"")"
[ "$got" = "$w/mgx/clang22-cross/bin/llvm-nm" ] || { echo "FAIL NM unset: an installed clang22-cross's llvm-nm: got $got"; exit 1; }
got="$(nm_resolve SHIPYARD_MG_PREFIX="$w/empty")"
[ "$got" = "$w/apple/nm" ] || { echo "FAIL last resort for NM: a bare nm on PATH: got $got"; exit 1; }
rc=0; env -u NM -u OTOOL -u LIPO PATH="$w/empty" SHIPYARD_MACHO_DIRS= SHIPYARD_MG_PREFIX="$w/empty" /bin/sh -c ". '$LIB'; mach_tool NM" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL no nm at all is a failure (1), got $rc"; exit 1; }

got="$(env OTOOL=/my/otool PATH="$w/clangbin" /bin/sh -c ". '$LIB'; mach_tool OTOOL && printf '%s\n' \"\$OTOOL\"")"
[ "$got" = /my/otool ] || { echo "FAIL a reader the caller named is kept: got $got"; exit 1; }

rc=0; env PATH="" /bin/sh -c ". '$LIB'; mach_tool FILE" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL an unknown reader is a usage error (2), got $rc"; exit 1; }

echo "PASS: macho-tools"
