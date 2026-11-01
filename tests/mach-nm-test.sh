#!/bin/sh
# platform: host-agnostic
#   usage: mach-nm-test.sh
#          With NM unset, the C++ runtime check reads Mach-O with the llvm-nm beside the LIPO/OTOOL the
#          caller chose, then an installed clang22's, and only then a bare nm: GNU nm (Linux) and the 10.9
#          CLT nm (arm64 slices) cannot read what it must. An explicit NM always wins.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../scripts/lib/mach-nm.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/mach-nm.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: mach-nm: $1"; exit 1; }
mkdir -p "$w/llvm/bin" "$w/empty"
for t in llvm-nm llvm-otool llvm-lipo; do printf '#!/bin/sh\n' > "$w/llvm/bin/$t"; chmod +x "$w/llvm/bin/$t"; done
[ "$(NM=/my/nm OTOOL="$w/llvm/bin/llvm-otool" shipyard_mach_nm)" = /my/nm ] || fail "an explicit NM wins"
[ "$(unset NM; OTOOL="$w/llvm/bin/llvm-otool" SHIPYARD_MG_PREFIX="$w/empty" shipyard_mach_nm)" = "$w/llvm/bin/llvm-nm" ] \
  || fail "NM unset: the llvm-nm beside OTOOL's llvm-otool"
[ "$(unset NM OTOOL; LIPO="$w/llvm/bin/llvm-lipo" SHIPYARD_MG_PREFIX="$w/empty" shipyard_mach_nm)" = "$w/llvm/bin/llvm-nm" ] \
  || fail "NM unset: the llvm-nm beside LIPO's llvm-lipo"
mkdir -p "$w/mg/clang22/bin"; cp "$w/llvm/bin/llvm-nm" "$w/mg/clang22/bin/"
[ "$(unset NM OTOOL LIPO; SHIPYARD_MG_PREFIX="$w/mg" shipyard_mach_nm)" = "$w/mg/clang22/bin/llvm-nm" ] \
  || fail "NM unset, no llvm readers chosen: an installed clang22's llvm-nm"
[ "$(unset NM OTOOL LIPO; SHIPYARD_MG_PREFIX="$w/empty" shipyard_mach_nm)" = nm ] || fail "last resort: nm"
echo "PASS: mach-nm"
