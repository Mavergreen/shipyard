#!/bin/sh
# platform: host-agnostic
#   usage: mach-tools-test.sh
#          shipyard_mach_tool: an explicit variable wins, then the llvm- tool beside one the caller chose;
#          macOS falls back to Apple's names, and anywhere else to an installed clang22's llvm- tools, else
#          the bare llvm- name, never the host's GNU ar, nm or strip.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../scripts/lib/mach-nm.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/mach-tools.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: mach-tools: $1"; exit 1; }
mkdir -p "$w/llvm/bin" "$w/mg/clang22/bin" "$w/empty"
for t in nm otool lipo ar strip install-name-tool; do
  printf '#!/bin/sh\n' > "$w/llvm/bin/llvm-$t"; chmod +x "$w/llvm/bin/llvm-$t"
  cp "$w/llvm/bin/llvm-$t" "$w/mg/clang22/bin/"
done
unset NM LIPO OTOOL AR STRIP INSTALL_NAME_TOOL
[ "$(AR=/my/ar SHIPYARD_MACH_HOST=Linux shipyard_mach_tool ar)" = /my/ar ] || fail "an explicit AR wins"
[ "$(INSTALL_NAME_TOOL=/my/int shipyard_mach_tool install-name-tool)" = /my/int ] || fail "an explicit INSTALL_NAME_TOOL wins"
[ "$(OTOOL="$w/llvm/bin/llvm-otool" SHIPYARD_MG_PREFIX="$w/empty" SHIPYARD_MACH_HOST=Darwin shipyard_mach_tool lipo)" = "$w/llvm/bin/llvm-lipo" ] \
  || fail "LIPO unset: the llvm-lipo beside OTOOL's llvm-otool, on macOS too"
[ "$(NM="$w/llvm/bin/llvm-nm" SHIPYARD_MG_PREFIX="$w/empty" SHIPYARD_MACH_HOST=Linux shipyard_mach_tool ar)" = "$w/llvm/bin/llvm-ar" ] \
  || fail "AR unset: the llvm-ar beside NM's llvm-nm"
for p in lipo:lipo otool:otool ar:ar strip:strip install-name-tool:install_name_tool; do
  [ "$(SHIPYARD_MG_PREFIX="$w/mg" SHIPYARD_MACH_HOST=Darwin shipyard_mach_tool "${p%%:*}")" = "${p#*:}" ] \
    || fail "macOS, nothing chosen: Apple's ${p#*:}"
done
for t in lipo otool nm ar strip install-name-tool; do
  [ "$(SHIPYARD_MG_PREFIX="$w/mg" SHIPYARD_MACH_HOST=Linux shipyard_mach_tool "$t")" = "$w/mg/clang22/bin/llvm-$t" ] \
    || fail "Linux, nothing chosen: the installed clang22's llvm-$t"
  [ "$(SHIPYARD_MG_PREFIX="$w/empty" SHIPYARD_MACH_HOST=Linux shipyard_mach_tool "$t")" = "llvm-$t" ] \
    || fail "Linux, no clang22: the bare llvm-$t, never the host's $t"
done
if shipyard_mach_tool ranlib > /dev/null 2>&1; then fail "an unknown tool is refused"; fi
echo "PASS: mach-tools"
