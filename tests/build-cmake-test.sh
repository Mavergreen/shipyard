#!/bin/sh
# platform: host-agnostic
#   usage: build-cmake-test.sh
#          build-cmake.sh must refuse bytes Kitware did not publish: the tarball is verified against
#          the release's own cmake-<v>-SHA-256.txt, fetched from the same place, so a tampered or
#          truncated download -- or a release whose checksum file does not list it -- fails BEFORE
#          anything is built.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/build-cmake.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/build-cmake-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
v="$(sed -n 's/^CMAKE_VERSION=//p' "$here/../cmake.pin")"
[ -n "$v" ] || { echo "FAIL: cmake.pin has no CMAKE_VERSION"; exit 1; }

rel="$work/rel/v$v"; mkdir -p "$rel"
echo "pretend source" > "$work/payload"; ( cd "$work" && tar -czf "$rel/cmake-$v.tar.gz" payload )
( cd "$rel" && shasum -a 256 "cmake-$v.tar.gz" > "cmake-$v-SHA-256.txt" )
base="file://$work/rel"

out="$(SHIPYARD_CMAKE_URL_BASE="$base" sh "$S" --fetch-only --dest "$work/d1")" \
  || { echo "FAIL: a tarball matching the published checksum must verify"; exit 1; }
[ -f "$out" ] || { echo "FAIL: --fetch-only must print the verified tarball's path; got '$out'"; exit 1; }

printf 'x' >> "$rel/cmake-$v.tar.gz"
if msg="$(SHIPYARD_CMAKE_URL_BASE="$base" sh "$S" --fetch-only --dest "$work/d2" 2>&1)"; then
  echo "FAIL: a tarball that does not match the published checksum must be refused"; exit 1
fi
printf '%s' "$msg" | grep -qi 'checksum' || { echo "FAIL: the refusal must say checksum; got: $msg"; exit 1; }

: > "$rel/cmake-$v-SHA-256.txt"
if SHIPYARD_CMAKE_URL_BASE="$base" sh "$S" --fetch-only --dest "$work/d3" >/dev/null 2>&1; then
  echo "FAIL: a checksum file without the tarball's line must be refused"; exit 1
fi

if sh "$S" --arch x86_64 >/dev/null 2>&1; then echo "FAIL: --arch without --min-os/--prefix must fail"; exit 1; fi

# spec: scripts/build-cmake.sh -- the configure needs CMAKE_SYSTEM_VERSION as a DARWIN release, and
#       the mapping is arithmetic on --min-os. A floor it cannot map must be refused here, before
#       anything is downloaded, rather than reaching cmake as an empty or nonsense version.
if msg="$(sh "$S" --arch x86_64 --min-os banana --prefix "$work/p" 2>&1)"; then
  echo "FAIL: an unmappable --min-os must be refused"; exit 1
fi
printf '%s' "$msg" | grep -q 'min-os' || { echo "FAIL: the refusal must name --min-os; got: $msg"; exit 1; }

# spec: scripts/build-cmake.sh -- CMake is configured by a host-native cmake now, not ./bootstrap,
#       so a box without one must say so and say what to install instead of failing later inside a
#       download or a configure.
if PATH=/usr/bin:/bin command -v cmake >/dev/null 2>&1; then
  echo "SKIP: a cmake is on the minimal PATH here, so the missing-host-cmake refusal cannot be exercised"
else
  if msg="$(PATH=/usr/bin:/bin sh "$S" --arch x86_64 --min-os 10.9 --prefix "$work/p" 2>&1)"; then
    echo "FAIL: no cmake on PATH must be refused"; exit 1
  fi
  printf '%s' "$msg" | grep -q 'cmake.org/download' \
    || { echo "FAIL: the refusal must name where to get a cmake; got: $msg"; exit 1; }
fi

echo "PASS: build-cmake"
