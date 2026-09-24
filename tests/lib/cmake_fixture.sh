# platform: host-agnostic
# spec: R-P1-21 -- shared by the three tests that build a fixture cmake PREFIX
#       (shipyard-cmake-refusal, msc-template, assert-installed-shipyard); tests/lib/ is not itself
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
