#!/bin/sh
# The shared hidden presets must declare a binaryDir that varies by checkout
# (via ${sourceDirName}), not a fixed path. shipyard itself has three
# checkouts in this tree and macho-tools has two path spellings -- a fixed
# name means two checkouts of the same repo share one CMakeCache.txt and
# CMake refuses to reconfigure ("does not match the source ... used to
# generate cache"). Their MAVERICKS_BUILD_ROOT default must also actually
# resolve through `inherits`.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
P="$root/mavericks-presets.json"
fails=0
say() { echo "FAIL: $1"; fails=$((fails+1)); }

if [ "$(grep -c '"binaryDir"' "$P" || true)" -ne 2 ]; then
  say "expected both hidden presets to declare binaryDir (a fixed default cannot tell two checkouts of the same repo apart)"
fi
if [ "$(grep -c '${sourceDirName}' "$P" || true)" -ne 2 ]; then
  say "expected both hidden presets' binaryDir to key off \${sourceDirName} so two checkouts do not collide"
fi
grep -q '"MAVERICKS_BUILD_ROOT": "\$penv{TMPDIR}/mm-build"' "$P" \
  || say "MAVERICKS_BUILD_ROOT is not defaulted to TMPDIR"

command -v cmake >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }

# A consumer no longer supplies its own binaryDir at all -- the hidden preset
# derives one from ${sourceDirName}, removing a per-repo chance to typo it.
fixture() {  # $1 = directory to populate as a CMake source root
  mkdir -p "$1"
  printf 'cmake_minimum_required(VERSION 3.25)\nproject(t C)\n' > "$1/CMakeLists.txt"
  cp "$P" "$1/mavericks-presets.json"
  cat > "$1/CMakePresets.json" <<'JSON'
{ "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 25, "patch": 0 },
  "include": ["mavericks-presets.json"],
  "configurePresets": [
    { "name": "native", "inherits": "mavericks-native" } ] }
JSON
}

# Two SEPARATE checkouts (distinct mktemp'd source roots) using the SAME
# preset -- this is the scenario a fixed binaryDir cannot survive. Each
# mktemp call gets a fresh random suffix, so $work1 and $work2 are unique to
# THIS run; no cross-run cleanup of a fixed build path is needed here (that
# was only ever required because the earlier design's binaryDir name did not
# vary by checkout), so the trap below is tidiness for this run's two build
# dirs, not collision avoidance.
work1="$(mktemp -d "${TMPDIR:-/tmp}/presets1.XXXXXX")"
work2="$(mktemp -d "${TMPDIR:-/tmp}/presets2.XXXXXX")"
b1="$(basename "$work1")"; b2="$(basename "$work2")"
bd1="${TMPDIR:-/tmp}/mm-build/${b1}-native"
bd2="${TMPDIR:-/tmp}/mm-build/${b2}-native"
trap 'rm -rf "$work1" "$work2" "$bd1" "$bd2"' EXIT INT TERM

fixture "$work1"
fixture "$work2"

out1="$(cd "$work1" && cmake --preset native 2>&1)" \
  || say "checkout 1 does not configure: $out1"
if [ -e "$work1/CMakeCache.txt" ]; then say "checkout 1 configured INSIDE its own source tree"; fi

out2="$(cd "$work2" && cmake --preset native 2>&1)" \
  || say "checkout 2 does not configure: $out2"
if [ -e "$work2/CMakeCache.txt" ]; then say "checkout 2 configured INSIDE its own source tree"; fi

[ -f "$bd1/CMakeCache.txt" ] \
  || say "checkout 1 did not build at the \${sourceDirName}-derived path $bd1 -- binaryDir is not keying off the checkout's name"
[ -f "$bd2/CMakeCache.txt" ] \
  || say "checkout 2 did not build at the \${sourceDirName}-derived path $bd2 -- binaryDir is not keying off the checkout's name"
if [ "$bd1" = "$bd2" ]; then say "two different checkouts resolved to the SAME build directory"; fi

# Reconfiguring checkout 1 a second time, after checkout 2 has also run,
# must still succeed. If the two checkouts had collided on one binaryDir,
# checkout 2's configure would have left a cache pointing at checkout 2's
# source path, and this call would fail with "does not match the source
# ... used to generate cache".
out1b="$(cd "$work1" && cmake --preset native 2>&1)" \
  || say "checkout 1 does not reconfigure after checkout 2 ran: $out1b"

[ "$fails" -eq 0 ] && echo "mavericks-presets: ok"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
