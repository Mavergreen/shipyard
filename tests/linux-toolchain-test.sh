#!/bin/sh
# platform: host-agnostic
set -eu
[ "$(uname -s)" = Linux ] || { echo 'SKIP: Linux CMake host configuration'; exit 77; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/linux-host.XXXXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/shipyard/scripts" "$T/project" "$T/SDK with spaces"
cp "$ROOT/MavergreenToolchain.cmake" "$T/shipyard/"
cat > "$T/shipyard/scripts/fetch_sdk.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$TEST_SDK"
SH
cat > "$T/shipyard/scripts/fetch_clang22.sh" <<'SH'
#!/bin/sh
[ -s "$1/.mavergreen/ingredients/clang22/VERSION" ] || { echo "fetch_clang22 stub: $1 pins no clang22" >&2; exit 2; }
printf '%s\n' "$TEST_LLVM"
SH
mkdir -p "$T/shipyard/.mavergreen/ingredients/clang22" "$T/llvm/bin"; echo 22.1.8-mavericks.26 > "$T/shipyard/.mavergreen/ingredients/clang22/VERSION"
for t in clang clang++ ld64.lld llvm-install-name-tool llvm-ar llvm-ranlib llvm-strip llvm-nm; do
  printf '#!/bin/sh\n' > "$T/llvm/bin/$t"; chmod 755 "$T/llvm/bin/$t"
done
export TEST_LLVM="$T/llvm"
cat > "$T/project/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(host_contract NONE)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "$ENV{TEST_ARCH}")
  message(FATAL_ERROR "Linux configure did not select Darwin/$ENV{TEST_ARCH}")
endif()
if(NOT CMAKE_CROSSCOMPILING)
  message(FATAL_ERROR "must not execute target probes as Linux programs")
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET STREQUAL "$ENV{TEST_FLOOR}")
  message(FATAL_ERROR "incorrect floor")
endif()
foreach(lang C OBJC CXX OBJCXX)
  set(want "$ENV{TEST_LLVM}/bin/clang")
  if(lang MATCHES "XX$")
    set(want "${want}++")
  endif()
  if(lang STREQUAL "C" AND DEFINED ENV{TEST_C})
    set(want "$ENV{TEST_C}")
  elseif(NOT CMAKE_${lang}_COMPILER_TARGET STREQUAL "$ENV{TEST_ARCH}-apple-macos$ENV{TEST_FLOOR}")
    message(FATAL_ERROR "${lang} targets '${CMAKE_${lang}_COMPILER_TARGET}', not the arch's floor")
  endif()
  if(NOT CMAKE_${lang}_COMPILER STREQUAL want)
    message(FATAL_ERROR "${lang} compiler is '${CMAKE_${lang}_COMPILER}', not ${want}")
  endif()
endforeach()
if(NOT MAVERGREEN_CLANG22 STREQUAL "$ENV{TEST_LLVM}")
  message(FATAL_ERROR "MAVERGREEN_CLANG22 is '${MAVERGREEN_CLANG22}', not the clang22 it chose")
endif()
get_filename_component(bdir "${CMAKE_BINARY_DIR}" REALPATH)
if(NOT CMAKE_EXE_LINKER_FLAGS_INIT STREQUAL "-fuse-ld=lld --ld-path=$ENV{TEST_LLVM}/bin/ld64.lld -Wl,-oso_prefix,${bdir}/")
  message(FATAL_ERROR "links with '${CMAKE_EXE_LINKER_FLAGS_INIT}', not clang22's ld64.lld")
endif()
get_filename_component(actual_sdk "${CMAKE_OSX_SYSROOT}" REALPATH)
get_filename_component(expected_sdk "$ENV{TEST_SDK}" REALPATH)
if(NOT actual_sdk STREQUAL expected_sdk)
  message(FATAL_ERROR "SDK path lost: ${CMAKE_OSX_SYSROOT} (expected $ENV{TEST_SDK})")
endif()
CMAKE
export TEST_SDK="$T/SDK with spaces"
TEST_ARCH=x86_64 TEST_FLOOR=10.9 cmake -S "$T/project" -B "$T/build" -DCMAKE_TOOLCHAIN_FILE="$T/shipyard/MavergreenToolchain.cmake"
TEST_ARCH=arm64 TEST_FLOOR=11.0 cmake -S "$T/project" -B "$T/arm" -DCMAKE_TOOLCHAIN_FILE="$T/shipyard/MavergreenToolchain.cmake" -DCMAKE_OSX_ARCHITECTURES=arm64
TEST_C=/bin/true TEST_ARCH=x86_64 TEST_FLOOR=10.9 cmake -S "$T/project" -B "$T/named" -DCMAKE_TOOLCHAIN_FILE="$T/shipyard/MavergreenToolchain.cmake" -DCMAKE_C_COMPILER=/bin/true
mkdir -p "$T/tools"
cat > "$T/tools/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(host_tools NONE)
foreach(pair INSTALL_NAME_TOOL=llvm-install-name-tool AR=llvm-ar RANLIB=llvm-ranlib STRIP=llvm-strip NM=llvm-nm)
  string(REPLACE "=" ";" pair "${pair}")
  list(GET pair 0 var)
  list(GET pair 1 tool)
  get_filename_component(have "${CMAKE_${var}}" REALPATH)
  get_filename_component(want "$ENV{TEST_LLVM}/bin/${tool}" REALPATH)
  if(NOT have STREQUAL want)
    message(FATAL_ERROR "CMAKE_${var} is '${CMAKE_${var}}', not the compiler's own ${tool}: a Linux host has no "
      "install_name_tool, and its ar, ranlib, strip and nm are binutils', which do not write Mach-O")
  endif()
endforeach()
CMAKE
TEST_LLVM="$T/llvm" cmake -S "$T/tools" -B "$T/tools-build" -DCMAKE_TOOLCHAIN_FILE="$T/shipyard/MavergreenToolchain.cmake" \
  -DCMAKE_OBJC_COMPILER="$T/llvm/bin/clang"
echo "PASS: Linux cross configuration selects the arch, its floor, the pinned SDK path, clang22 for every unnamed compiler and its Mach-O tools"
