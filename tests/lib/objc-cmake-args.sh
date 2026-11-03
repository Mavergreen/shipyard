# platform: host-agnostic
# usage: . objc-cmake-args.sh; objc_cmake_args ROOT; objc_cmake ARG...  -- objc_cmake_args sets CMAKE
#        and exports clang22's Mach-O readers as LIPO, OTOOL, NM and STRINGS for the compat guard a
#        build runs; objc_cmake then runs $CMAKE with ARG... and the arguments that configure and
#        build Objective-C exactly as tests/lib/build-updater.sh does, with the pinned clang22 and
#        ROOT's MavericksToolchain.cmake, x86_64 against the 10.9 SDK.
objc_cmake_args() {
  CMAKE="${CMAKE:-$(command -v shipyard-cmake || echo cmake)}"
  _oc_cl="$(sh "$1/scripts/fetch_clang22.sh" "$1")" || return 1
  _oc_root="$1"
  LIPO="$_oc_cl/bin/llvm-lipo"; OTOOL="$_oc_cl/bin/llvm-otool"; NM="$_oc_cl/bin/llvm-nm"; STRINGS="$_oc_cl/bin/llvm-strings"
  export LIPO OTOOL NM STRINGS
}
objc_cmake() {
  "$CMAKE" "$@" "-DCMAKE_TOOLCHAIN_FILE=$_oc_root/MavericksToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    "-DCMAKE_OBJC_COMPILER=$_oc_cl/bin/clang" -DCMAKE_OBJC_COMPILER_TARGET=x86_64-apple-macos10.9 \
    -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld
}
