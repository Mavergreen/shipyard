#!/bin/sh
# platform: host-agnostic
#   usage: cargo-env.sh [--sh] [--arch x86_64|arm64] [--rust PREFIX] [--clang22 PREFIX] [--sdk SDK] RUST_PIN_DIR [CLANG22_PIN_DIR]
#          Prints the environment a cargo build of a Rust product for Mac OS X 10.9 x86_64 needs, on an
#          x86_64 Linux host or an x86_64 Mac alike, one NAME=VALUE line each, for "$GITHUB_ENV"; with
#          --sh, as `export NAME='VALUE'` lines for eval. The toolchain is fetch_rust.sh RUST_PIN_DIR (a
#          product's components/rust), the compiler and linker fetch_clang22.sh CLANG22_PIN_DIR
#          (default: shipyard's own components/clang22), and the SDK fetch_sdk.sh's x86_64 pin;
#          --rust, --clang22 and --sdk name them instead. The lines:
#            CARGO RUSTC RUSTDOC          the pinned toolchain's
#            CARGO_BUILD_TARGET           x86_64-apple-darwin, so a bare cargo build targets 10.9
#            CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER    clang22's clang++, whose clang.cfg links Recaulk
#            CC_x86_64_apple_darwin CXX_x86_64_apple_darwin AR_x86_64_apple_darwin
#            RANLIB_x86_64_apple_darwin   clang22's, for the cc crate
#            SDKROOT MACOSX_DEPLOYMENT_TARGET           the pinned 10.9 SDK, and 10.9
#            LIPO OTOOL NM AR STRIP INSTALL_NAME_TOOL STRINGS    clang22's llvm- tools
#          On Linux, host build scripts and proc macros still build for the host and link with its cc,
#          so a Linux host with no cc is refused; on a Mac the host is the target. A path holding
#          whitespace is refused (cargo splits flags on it). Exit 1 when a part cannot be fetched or
#          lacks a tool; 2 on a usage error.
#          --arch arm64 (default x86_64) targets macOS 11.0 arm64 with the 11.3 SDK instead, scoped to
#          aarch64-apple-darwin: CARGO_BUILD_TARGET aarch64-apple-darwin, MACOSX_DEPLOYMENT_TARGET 11.0,
#          CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER and CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
#          (clang22 without its cfg, lld, the SDK), CC_/CXX_/AR_/RANLIB_aarch64_apple_darwin, and
#          CFLAGS_/CXXFLAGS_aarch64_apple_darwin (the SDK; C++ takes the SDK's own libc++ headers).
#          No SDKROOT is set, so host build scripts never see a macOS SDK. The pinned rust must carry
#          lib/rustlib/aarch64-apple-darwin, else exit 1. CARGO_ENV_HOST replaces uname -s (test-only).
set -eu
S="$(cd "$(dirname "$0")" && pwd)"
die() { echo "cargo-env: $*" >&2; exit 1; }
usage() { echo "usage: cargo-env.sh [--sh] [--arch x86_64|arm64] [--rust PREFIX] [--clang22 PREFIX] [--sdk SDK] RUST_PIN_DIR [CLANG22_PIN_DIR]" >&2; exit 2; }
SH=""; R=""; CL=""; SDK=""; ARCH=x86_64
while [ $# -gt 0 ]; do
  case "$1" in
    --sh) SH=1; shift ;;
    --arch)
      [ $# -ge 2 ] || usage
      case "$2" in x86_64|arm64) ARCH=$2 ;; *) usage ;; esac
      shift 2 ;;
    --rust|--clang22|--sdk)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in --rust) R=$2 ;; --clang22) CL=$2 ;; --sdk) SDK=$2 ;; esac
      shift 2 ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] && [ $# -le 2 ] || usage
[ -d "$1" ] || { echo "cargo-env: $1 is not a components/rust directory" >&2; exit 2; }
CPIN="${2:-$S/../components/clang22}"
[ -d "$CPIN" ] || { echo "cargo-env: $CPIN is not a components/clang22 directory" >&2; exit 2; }
if [ "${CARGO_ENV_HOST:-$(uname -s)}" != Darwin ]; then
  command -v cc > /dev/null 2>&1 || die "no cc on PATH, which cargo links this host's build scripts and proc macros with; install gcc"
fi
[ -n "$R" ] || R="$(sh "$S/fetch_rust.sh" "$1")" || die "fetch_rust.sh could not provide the pinned rust"
[ -n "$CL" ] || CL="$(sh "$S/fetch_clang22.sh" "$CPIN")" || die "fetch_clang22.sh could not provide the pinned clang22"
[ -n "$SDK" ] || SDK="$(sh "$S/fetch_sdk.sh" --arch "$ARCH")" || die "fetch_sdk.sh could not provide the $ARCH SDK"
for p in "$R" "$CL" "$SDK"; do
  case "$p" in *[[:space:]]*) die "$p holds whitespace, which cargo would split inside its flags" ;; esac
done
for t in cargo rustc rustdoc; do [ -x "$R/bin/$t" ] || die "$R has no bin/$t"; done
for t in clang clang++ llvm-ar llvm-ranlib llvm-lipo llvm-otool llvm-nm llvm-strip llvm-install-name-tool llvm-strings; do
  [ -x "$CL/bin/$t" ] || die "$CL has no bin/$t"
done
[ "$ARCH" != arm64 ] || [ -d "$R/lib/rustlib/aarch64-apple-darwin" ] || die "$R has no lib/rustlib/aarch64-apple-darwin, so it cannot target arm64"
[ -d "$SDK/usr/include" ] || die "$SDK is not an SDK (no usr/include)"
line() {
  if [ -n "$SH" ]; then
    printf "export %s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"
  else
    printf '%s=%s\n' "$1" "$2"
  fi
}
line CARGO "$R/bin/cargo"
line RUSTC "$R/bin/rustc"
line RUSTDOC "$R/bin/rustdoc"
if [ "$ARCH" = arm64 ]; then
  line CARGO_BUILD_TARGET aarch64-apple-darwin
  line CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER "$CL/bin/clang++"
  line CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS "-C link-arg=--no-default-config -C link-arg=-fuse-ld=lld -C link-arg=-isysroot -C link-arg=$SDK"
  line CC_aarch64_apple_darwin "$CL/bin/clang"
  line CXX_aarch64_apple_darwin "$CL/bin/clang++"
  line AR_aarch64_apple_darwin "$CL/bin/llvm-ar"
  line RANLIB_aarch64_apple_darwin "$CL/bin/llvm-ranlib"
  line CFLAGS_aarch64_apple_darwin "--no-default-config --target=arm64-apple-macos11.0 -isysroot $SDK"
  line CXXFLAGS_aarch64_apple_darwin "--no-default-config --target=arm64-apple-macos11.0 -isysroot $SDK -nostdinc++ -isystem $SDK/usr/include/c++/v1"
  line MACOSX_DEPLOYMENT_TARGET 11.0
else
  line CARGO_BUILD_TARGET x86_64-apple-darwin
  line CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER "$CL/bin/clang++"
  line CC_x86_64_apple_darwin "$CL/bin/clang"
  line CXX_x86_64_apple_darwin "$CL/bin/clang++"
  line AR_x86_64_apple_darwin "$CL/bin/llvm-ar"
  line RANLIB_x86_64_apple_darwin "$CL/bin/llvm-ranlib"
  line SDKROOT "$SDK"
  line MACOSX_DEPLOYMENT_TARGET 10.9
fi
line LIPO "$CL/bin/llvm-lipo"
line OTOOL "$CL/bin/llvm-otool"
line NM "$CL/bin/llvm-nm"
line AR "$CL/bin/llvm-ar"
line STRIP "$CL/bin/llvm-strip"
line INSTALL_NAME_TOOL "$CL/bin/llvm-install-name-tool"
line STRINGS "$CL/bin/llvm-strings"
