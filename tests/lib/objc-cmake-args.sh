# platform: host-agnostic
# usage: . objc-cmake-args.sh; objc_cmake_args ROOT  -- sets CMAKE and OBJC_ARGS so a test configures
#        and builds Objective-C exactly as tests/lib/build-updater.sh does, with the pinned clang22 and
#        MavericksToolchain.cmake, x86_64 against the 10.9 SDK, and exports clang22's Mach-O readers as
#        LIPO, OTOOL, NM and STRINGS for the compat guard a build runs.
objc_cmake_args() {
  CMAKE="${CMAKE:-$(command -v shipyard-cmake || echo cmake)}"
  _cl="$(sh "$1/scripts/fetch_clang22.sh" "$1/components/clang22")" || return 1
  LIPO="$_cl/bin/llvm-lipo"; OTOOL="$_cl/bin/llvm-otool"; NM="$_cl/bin/llvm-nm"; STRINGS="$_cl/bin/llvm-strings"
  export LIPO OTOOL NM STRINGS
  OBJC_ARGS="-DCMAKE_TOOLCHAIN_FILE=$1/MavericksToolchain.cmake -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OBJC_COMPILER=$_cl/bin/clang -DCMAKE_OBJC_COMPILER_TARGET=x86_64-apple-macos10.9 -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld"
}
