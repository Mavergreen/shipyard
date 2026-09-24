#!/bin/sh
# platform: host-agnostic
#   usage: cmake-fixture-test.sh
#          Drives tests/lib/cmake_fixture.sh's copy_cmake_root against the shape that broke three
#          tests on macos-26 and could not break anything here: a read-only real tree plus a symlink
#          named `cmake` pointing at it, built out of ordinary directories so no Homebrew is needed
#          and a 10.9 box still catches a regression. Exit 0 clean, 1 on failure.
# spec: R-P1-21 -- the two hazardous properties are Homebrew's alone (a SYMLINK at share/cmake, the
#       very path shipyard installs into, and a READ-ONLY tree whose mode `cp -R` preserves), and a
#       pkgsrc box has neither. tests/lib/cmake_fixture.sh states them in full.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/cmake_fixture.sh"

w="$(mktemp -d "${TMPDIR:-/tmp}/cmake-fixture-test.XXXXXX")"
# platform: the host tree is read-only, so rm -rf cannot clear it without taking the write bit back
#           first.
trap 'chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT

host="$w/host"                        # stands in for /opt/homebrew/Cellar/cmake/X/share/cmake
mkdir -p "$host/Modules"
printf 'the host cmake owns this\n' > "$host/Modules/FindFoo.cmake"
# platform: a packaged cmake is full of symlinks INSIDE the tree pointing out of it. Without -L the
#           copy keeps them as links and anything the fixture writes there lands outside the
#           fixture; the trailing "/." alone dereferences only the top-level source.
printf 'outside the fixture\n' > "$w/outside.txt"
ln -s ../../outside.txt "$host/Modules/Outside.cmake"
ln -s host "$w/cmake"                 # ...reached as /opt/homebrew/share/cmake, a symlink named `cmake`
chmod -R a-w "$host"

fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

naive="$w/naive/share"; mkdir -p "$naive"
cp -R "$w/cmake" "$naive/cmake"
[ -L "$naive/cmake" ] \
  || fail "cp -R of a symlinked CMAKE_ROOT no longer yields a symlink on this platform -- if BSD cp " \
          "changed, the helper's -L is still correct but this test no longer proves why"

# platform: the parent exists already, as in every real caller. Without it a naive `cp -R` fails for
#           the uninteresting reason that its destination's parent is missing, and this test would
#           "pass" against a helper that had regressed.
dest="$w/fx/share/cmake"; mkdir -p "$w/fx/share"
copy_cmake_root "$w/cmake" "$dest"

[ ! -L "$dest" ] || fail "copy_cmake_root left $dest a SYMLINK; anything installed into the fixture " \
                         "would land in the host's own cmake tree"
[ -d "$dest" ] || fail "copy_cmake_root did not produce a directory at $dest"
[ -f "$dest/Modules/FindFoo.cmake" ] || fail "copy_cmake_root did not copy the tree's contents"

# platform: `mkdir -p` gives the top level a mode of its own and only the subdirectories carry the
#           source's, so writability is checked at the top of the copy AND inside it.
mkdir "$dest/MavericksShipyard" 2>/dev/null \
  || fail "cannot create $dest/MavericksShipyard -- the copy kept the host's read-only mode, which is " \
          "exactly the macos-26 failure ('Maybe need administrative privileges')"
mkdir "$dest/Modules/Sub" 2>/dev/null \
  || fail "cannot create a directory INSIDE the copied tree; the copy kept the host's read-only mode"
printf 'x\n' > "$dest/Modules/FindFoo.cmake" 2>/dev/null \
  || fail "cannot overwrite a file in the copy; the fixture does not own what it must write into"

[ ! -L "$dest/Modules/Outside.cmake" ] \
  || fail "copy_cmake_root kept an internal symlink as a link; the fixture can write outside itself"
printf 'the fixture wrote this\n' > "$dest/Modules/Outside.cmake" 2>/dev/null \
  || fail "cannot write $dest/Modules/Outside.cmake"
[ "$(cat "$w/outside.txt")" = "outside the fixture" ] \
  || fail "writing inside the fixture changed $w/outside.txt -- an internal symlink was followed out"

[ ! -e "$host/MavericksShipyard" ] || fail "the host tree gained MavericksShipyard -- the fixture wrote THROUGH to it"
[ "$(cat "$host/Modules/FindFoo.cmake")" = "the host cmake owns this" ] \
  || fail "the host tree's contents changed -- the fixture wrote THROUGH to it"

[ "$fails" -eq 0 ] || { echo "FAIL: $fails case(s) in cmake-fixture"; exit 1; }
echo "PASS: cmake-fixture"
