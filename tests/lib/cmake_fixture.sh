# platform: host-agnostic
# spec: R-P1-21 -- shared by the three tests that build a fixture <root>/{shipyard,cmake} pair
#       (shipyard-cmake-refusal, shipyard-scripts, assert-installed-shipyard); tests/lib/ is not itself
#       run, since run-repo-tests.sh takes top-level tests only.
# platform: Homebrew's CMAKE_ROOT is <prefix>/share/cmake -- the very path shipyard installs into --
#           and is itself a SYMLINK, while BSD `cp -R` copies a symlink AS a symlink: the fixture's
#           share/cmake would alias Homebrew's real share directory and the `cmake --install` two
#           lines later would create MavericksShipyard INSIDE the host's own cmake installation.
#           Homebrew's tree is also read-only and `cp -R` preserves the source's mode, so even a
#           materialised copy could not be installed into ("file cannot create directory: ... Maybe
#           need administrative privileges"). Both are INVISIBLE on a pkgsrc cmake (share/cmake-X.Y,
#           writable), and together they reddened all three tests on every macos-26 runner while all
#           three passed here. Hence: materialise (-L), copy the CONTENTS into a directory the test
#           made itself ("/." plus a trailing "/"), and take ownership of the result.
# spec: tests/cmake-fixture-test.sh -- drives this against a symlinked, read-only source named
#       `cmake`, the Homebrew shape, runnably on a 10.9 box with a pkgsrc cmake.
#   usage: copy_cmake_root <CMAKE_ROOT> <destination dir>
copy_cmake_root() {
  mkdir -p "$2"
  cp -RL "$1"/. "$2"/
  chmod -R u+w "$2"
}

# spec: 2026-10-09 C4 -- copy_cmake_product <host cmake> <root>/cmake stands in for the cmake product
#       beside shipyard: the host cmake COPIED with its CMAKE_ROOT, since a cmake finds CMAKE_ROOT
#       beside its real path.
copy_cmake_product() {
  mkdir -p "$2/bin" "$2/share"
  cp "$1" "$2/bin/cmake"
  printf 'message("${CMAKE_ROOT}")\n' > "$2/root.cmake"
  _ccp_root="$("$1" -P "$2/root.cmake" 2>&1)"
  rm -f "$2/root.cmake"
  copy_cmake_root "$_ccp_root" "$2/share/${_ccp_root##*/}"
}
