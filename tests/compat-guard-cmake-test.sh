#!/bin/sh
# platform: host-agnostic
#   usage: compat-guard-cmake-test.sh
#          mavericks_assert_binary_compatible() hands the guard MAVERICKS_DEVIATIONS_ROOT = the
#          project's CMAKE_SOURCE_DIR. A POST_BUILD command runs in the build tree, so without it the
#          guard would look there for INGREDIENTS.md and honour no sdk-pin:<glob> exemption at all.
# platform: script mode (cmake -P) sets CMAKE_SOURCE_DIR to the working directory and cannot run
#           add_custom_command, so the probe stands its own in to record what the module asks for --
#           no compiler, no project, and it runs wherever cmake does.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
command -v cmake >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
w="$(mktemp -d "${TMPDIR:-/tmp}/guard-cmake-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
src="$(cd "$w" && pwd -P)"
cat > "$src/probe.cmake" <<EOF
function(add_custom_command)
  message("ARGS: \${ARGN}")
endfunction()
include("$root/MavericksCompatGuard.cmake")
mavericks_assert_binary_compatible(foo)
EOF
out="$(cd "$src" && cmake -P probe.cmake 2>&1)" || { echo "FAIL: the probe did not run:"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q ";MAVERICKS_DEVIATIONS_ROOT=$src;" \
  || { echo "FAIL: the guard is not given MAVERICKS_DEVIATIONS_ROOT=$src (CMAKE_SOURCE_DIR):"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q ";-E;env;.*;sh;.*/assert_binary_compatible.sh;" \
  || { echo "FAIL: the variable must reach the guard's own environment:"; echo "$out"; exit 1; }
echo "PASS: compat-guard-cmake"
