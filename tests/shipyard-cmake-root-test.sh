#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
command -v cmake >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
work="$(mktemp -d "${TMPDIR:-/tmp}/shipyard-cmakeroot.XXXXXX")"; trap 'rm -rf "$work"' EXIT

mkdir -p "$work/a/.mavergreen/upstream" "$work/other/.mavergreen/upstream"
printf '1.0\n' > "$work/a/.mavergreen/upstream/VERSION"
printf '9.9\n' > "$work/other/.mavergreen/upstream/VERSION"
cat > "$work/a/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.5)
project(p NONE)
include("$root/MavericksVersion.cmake")
mavericks_resolve_version(V)
message(STATUS "resolved=\${V}")
EOF
out="$(MAVERGREEN_ROOT="$work/other" cmake -S "$work/a" -B "$work/b" 2>&1)" || { echo "FAIL: configure failed: $out"; exit 1; }
case "$out" in
  *"resolved=1.0-"*) ;;
  *) echo "FAIL: an inherited MAVERGREEN_ROOT must not change the version resolved for the configured repo: $out"; exit 1 ;;
esac
echo "PASS: shipyard-cmake-root"
