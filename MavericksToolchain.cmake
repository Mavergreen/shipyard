# MavericksToolchain.cmake -- a CMake toolchain file: the family's PINNED SDK, arch and deployment target,
# set BEFORE project() so compiler detection and find_library see the pinned SDK (a sysroot set later
# misses both -- the SDK-pinning spike's porthole could not find Cocoa that way). One arch per configure:
#   x86_64 (default) -> MacOSX10.9.sdk, deployment target 10.9
#   arm64            -> MacOSX11.3.sdk, deployment target 11.0
# On a 10.9 host (native mode, x86_64 only) the sysroot is pinned too: Xcode 6.1+ defaults to the 10.10
# SDK there, so it is xcrun's own 10.9 SDK when xcrun finds one, else the fetched pin. Package-time
# conformance verifies what each build records. Pins: scripts/sdk-pins.sh; rule: SKILL.md "SDK pinning".
# Use it via the shipyard presets (mavericks-cross / mavericks-native) or -DCMAKE_TOOLCHAIN_FILE=<this>.
if(NOT CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_OSX_ARCHITECTURES x86_64 CACHE STRING "one arch per configure" FORCE)
endif()
list(LENGTH CMAKE_OSX_ARCHITECTURES _mav_n)
if(NOT _mav_n EQUAL 1)
  message(FATAL_ERROR "MavericksToolchain.cmake: one arch per configure (got '${CMAKE_OSX_ARCHITECTURES}') -- "
                      "each arch pins a different SDK; build each and merge with lipo-merge-tree.sh")
endif()
if(CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64")
  set(_mav_target 10.9)
elseif(CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
  set(_mav_target 11.0)
else()
  message(FATAL_ERROR "MavericksToolchain.cmake: arch '${CMAKE_OSX_ARCHITECTURES}' has no pinned SDK (x86_64 and arm64 do)")
endif()
set(CMAKE_OSX_DEPLOYMENT_TARGET "${_mav_target}" CACHE STRING "pinned per arch" FORCE)

execute_process(COMMAND sw_vers -productVersion OUTPUT_VARIABLE _mav_osv
                OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
set(_mav_sdk "")
if(_mav_osv MATCHES "^10\\.9\\.")
  if(NOT CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64")
    message(FATAL_ERROR "MavericksToolchain.cmake: a native build (on 10.9) is x86_64 only (got '${CMAKE_OSX_ARCHITECTURES}') -- "
                        "build ${CMAKE_OSX_ARCHITECTURES} cross, on a modern host")
  endif()
  # A 10.9 SDK that xcrun cannot find, or that it names but is not there, falls back to the fetched pin.
  execute_process(COMMAND xcrun --sdk macosx10.9 --show-sdk-path OUTPUT_VARIABLE _mav_sdk
                  OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE _mav_xrc ERROR_QUIET)
  if(NOT _mav_xrc EQUAL 0 OR _mav_sdk STREQUAL "" OR NOT IS_DIRECTORY "${_mav_sdk}")
    set(_mav_sdk "")
  endif()
endif()
if(_mav_sdk STREQUAL "")
  execute_process(
    COMMAND sh "${CMAKE_CURRENT_LIST_DIR}/scripts/fetch_sdk.sh" --arch "${CMAKE_OSX_ARCHITECTURES}"
    OUTPUT_VARIABLE _mav_sdk OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE _mav_rc)
  if(NOT _mav_rc EQUAL 0)
    message(FATAL_ERROR "MavericksToolchain.cmake: fetch_sdk.sh --arch ${CMAKE_OSX_ARCHITECTURES} failed")
  endif()
endif()
set(CMAKE_OSX_SYSROOT "${_mav_sdk}" CACHE PATH "the pinned SDK" FORCE)
