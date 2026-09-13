#!/bin/sh
#   usage: register-with-cmake.sh <payload-dir> [home]
#          Points cmake at an installed shipyard payload. Called by the pkg's postinstall, and by hand
#          -- it is the documented recovery when shipyard was installed before cmake was.
# spec: tests/register-with-cmake-test.sh -- find_package() depends on the cmake BINARY's own
#       CMAKE_SYSTEM_PREFIX_PATH, not on where the payload sits, so this records the location in the
#       user package registry instead; the entry filename is FIXED (matching what CMakeLists.txt
#       writes on `cmake --install`), so registering twice replaces the path and never needs a
#       migration step.
set -eu
payload="${1:?register-with-cmake: payload dir required}"
home="${2:-$HOME}"

[ -d "$payload" ] || { echo "register-with-cmake: no such payload dir: $payload" >&2; exit 1; }

command -v cmake >/dev/null 2>&1 || {
  echo "register-with-cmake: cmake is not on PATH, so shipyard's CMake side cannot be registered." >&2
  echo "    shipyard's shell scripts are installed and usable now." >&2
  echo "    fix: install cmake (any cmake -- we do not care which), then run:" >&2
  echo "         sh $payload/scripts/register-with-cmake.sh $payload" >&2
  exit 1
}

reg="$home/.cmake/packages/MavericksShipyard"
mkdir -p "$reg"
printf '%s' "$payload" > "$reg/mavericks-shipyard"
echo "registered MavericksShipyard -> $payload"
