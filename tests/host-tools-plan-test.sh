#!/bin/sh
# platform: host-agnostic
# usage: sh tests/host-tools-plan-test.sh
#        mavericks_build_host_tools' host selection and configure arguments, with a fake sysctl: Apple
#        Silicon hardware is arm64/SDK 11.3/min 11.0 even when the caller is translated; anything else
#        is x86_64/SDK 10.9/min 10.9; the compiler's default config is off and no product setting leaks in.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
fx="$here/fixtures/host-tools"
SC="${CMAKE:-$(command -v shipyard-cmake || command -v cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)}"
[ -x "$SC" ] || command -v "$SC" >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/host-tools-plan.XXXXXX")"
trap 'rm -rf "$w"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

plan() {
  "$SC" -DMODULE_DIR="$root" -DSYSCTL="$fx/sysctl" -DCOMPILER=/opt/clang22/bin/clang -DOUT="$w/$1" \
    -P "$fx/plan.cmake" > "$w/$1.log" 2>&1 || { bad "$1: plan failed: $(cat "$w/$1.log")"; : > "$w/$1"; }
}
has() { grep -qxF -- "$2" "$w/$1" || bad "$1: no line '$2'"; }
lacks() { if grep -q -- "$2" "$w/$1"; then bad "$1: has '$2': $(grep -- "$2" "$w/$1" | head -1)"; fi; }

echo "== native_host_selection"
FAKE_ARM64=0 FAKE_TRANSLATED=0 plan native
has native arch=x86_64
has native target=x86_64-apple-macos10.9
has native min=10.9
has native -DCMAKE_OSX_ARCHITECTURES=x86_64
has native -DCMAKE_OSX_DEPLOYMENT_TARGET=10.9
has native -DCMAKE_OSX_SYSROOT=/sdk/for/x86_64
has native -DCMAKE_C_COMPILER_TARGET=x86_64-apple-macos10.9

echo "== arm64_hardware_from_translated_caller"
FAKE_ARM64=1 FAKE_TRANSLATED=1 plan arm64
has arm64 arch=arm64
has arm64 target=arm64-apple-macos11.0
has arm64 min=11.0
has arm64 -DCMAKE_OSX_ARCHITECTURES=arm64
has arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
has arm64 -DCMAKE_OSX_SYSROOT=/sdk/for/arm64
lacks arm64 x86_64
lacks arm64 availability_version_check

echo "== separate_target_config"
for p in native arm64; do
  lacks "$p" CMAKE_TOOLCHAIN_FILE
  lacks "$p" -ivfsoverlay
  lacks "$p" -isystem
  lacks "$p" -isysroot
  has "$p" -S/src
  has "$p" -B/build
  has "$p" -DCMAKE_C_COMPILER=/opt/clang22/bin/clang
  has "$p" -DCMAKE_MAKE_PROGRAM=/usr/bin/make
  has "$p" "-GUnix Makefiles"
  has "$p" -DCMAKE_POLICY_VERSION_MINIMUM=3.5
done
grep -qi recaulk "$w/native" "$w/arm64" && bad "a host configure names Recaulk"

echo "== compiler_default_config_disabled"
for p in native arm64; do
  has "$p" -DCMAKE_C_FLAGS=--no-default-config
done
grep -q -- '-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld' "$w/native" || bad "native: not linked with lld"
grep -q -- '-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld' "$w/arm64" || bad "arm64: not linked with lld"

echo "== cache_key_inputs"
keys="$(sed -n 's/^keys=//p' "$w/native")"
again="$(sed -n 's/^key-again=//p' "$w/native")"
n="$(printf '%s\n' $keys | sort -u | wc -l | tr -d ' ')"
[ "$n" = 6 ] || bad "changing the arch, compiler, SDK pin, source or implementation must each change the key: $keys"
[ "$again" = "$(printf '%s\n' $keys | head -1)" ] || bad "the same inputs gave another key"

echo "== installed_layout"
if "$SC" -S "$root" -B "$w/ib" -DCMAKE_INSTALL_PREFIX="$w/inst" > "$w/ib.log" 2>&1 \
   && "$SC" --install "$w/ib" > "$w/inst.log" 2>&1; then
  d="$(dirname "$(find "$w/inst" -name MavericksShipyardConfig.cmake | head -1)")"
  for f in MavericksHostTools.cmake tools/CMakeLists.txt components/mulle-xcode-to-cmake/version scripts/sdk-pins.sh \
           scripts/fetch_pinned_source.sh scripts/fetch_sdk.sh; do
    [ -f "$d/$f" ] || bad "installed_layout: the install lacks $f beside the module"
  done
else
  bad "installed_layout: could not install shipyard: $(tail -5 "$w/ib.log" "$w/inst.log" 2>/dev/null)"
fi

[ "$fail" -eq 0 ] && echo "host-tools-plan-test: OK"
exit "$fail"
