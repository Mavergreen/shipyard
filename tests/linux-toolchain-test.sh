#!/bin/sh
# platform: host-agnostic
set -eu
[ "$(uname -s)" = Linux ] || { echo 'SKIP: Linux CMake host configuration'; exit 77; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/linux-host.XXXXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/shipyard/scripts" "$T/project" "$T/SDK with spaces"
cp "$ROOT/MavericksToolchain.cmake" "$T/shipyard/"
cat > "$T/shipyard/scripts/fetch_sdk.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$TEST_SDK"
SH
cat > "$T/project/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(host_contract NONE)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
  message(FATAL_ERROR "Linux configure did not select Darwin/x86_64")
endif()
if(NOT CMAKE_CROSSCOMPILING)
  message(FATAL_ERROR "must not execute target probes as Linux programs")
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET STREQUAL "10.9")
  message(FATAL_ERROR "incorrect floor")
endif()
get_filename_component(actual_sdk "${CMAKE_OSX_SYSROOT}" REALPATH)
get_filename_component(expected_sdk "$ENV{TEST_SDK}" REALPATH)
if(NOT actual_sdk STREQUAL expected_sdk)
  message(FATAL_ERROR "SDK path lost: ${CMAKE_OSX_SYSROOT} (expected $ENV{TEST_SDK})")
endif()
CMAKE
export TEST_SDK="$T/SDK with spaces"
cmake -S "$T/project" -B "$T/build" -DCMAKE_TOOLCHAIN_FILE="$T/shipyard/MavericksToolchain.cmake"
if cmake -S "$T/project" -B "$T/arm" -DCMAKE_TOOLCHAIN_FILE="$T/shipyard/MavericksToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES=arm64 > "$T/arm.log" 2>&1; then
  echo 'FAIL: accepted unsupported Linux arm64 target'; exit 1
fi
grep -q 'Linux.*x86_64' "$T/arm.log"
echo 'PASS: Linux cross configuration, pinned SDK path and unsupported target refusal'
