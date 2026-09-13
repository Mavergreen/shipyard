#!/bin/sh
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

echo "PASS: build-cmake"
