# Mavericks.cmake -- shared build conventions for the mavericks-* family.
#
# These projects all build native artifacts that run on OS X 10.9 "Mavericks"
# and cross-build for it from a modern macOS on GitHub Actions. This module
# centralizes what that takes; each project keeps its own targets/packaging.
#
# Usage (in a project CMakeLists.txt): every mavericks-* project can include this.
#
#   project(foo LANGUAGES C OBJC)
#
#   find_package(MavericksShipyard REQUIRED)   # sets up CMAKE_MODULE_PATH
#   include(Mavericks)                 # mode detect + AppleClang check + helpers
#   # (Sparkle-updater projects also: include(MavericksSparkle))
#
#   add_executable(foo ...)
#   mavericks_assert_binary_compatible(foo)        # assert the binary stays 10.9-safe
#
# Deployment target + architecture must be set BEFORE project() to take effect, so
# they come from your preset (inherit mavericks-native / mavericks-cross from
# mavericks-presets.json) -- NOT from this umbrella, which runs after project(). A
# project on a non-Apple toolchain sets(MAVERICKS_REQUIRE_APPLECLANG OFF) first.
# Install once with `cmake --install` (self-registers); see README.

set(MAVERICKS_SHARED_DIR "${CMAKE_CURRENT_LIST_DIR}" CACHE INTERNAL "mavericks-shipyard root")

# Newer SDKs deprecate the 10.9-era Cocoa/IOKit APIs these projects use; we still
# target them deliberately. (Deployment target + arch are the consumer's, set before
# project() via the preset -- this umbrella runs too late to set them.)
add_compile_options(-Wall -Wno-deprecated-declarations)

include(MavericksMode)          # -> MAVERICKS_MODE, guard vs the preset's expected mode

# SKILL.md "SDK pinning": a cross build links the PINNED SDK for its arch, never the runner's. The
# toolchain file (via the shipyard presets) sets it before project(); anything else is refused here, the
# earliest point shipyard runs, rather than discovered at package time.
if(MAVERICKS_MODE STREQUAL "cross")
  list(LENGTH CMAKE_OSX_ARCHITECTURES _mav_na)
  if(_mav_na EQUAL 1)
    execute_process(COMMAND sh "${MAVERICKS_SHARED_DIR}/scripts/fetch_sdk.sh" --arch "${CMAKE_OSX_ARCHITECTURES}"
                    OUTPUT_VARIABLE _mav_pin OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE _mav_prc)
    get_filename_component(_mav_have "${CMAKE_OSX_SYSROOT}" REALPATH)
    get_filename_component(_mav_want "${_mav_pin}" REALPATH)
    if(NOT _mav_prc EQUAL 0 OR NOT _mav_have STREQUAL _mav_want)
      message(FATAL_ERROR
        "CMAKE_OSX_SYSROOT '${CMAKE_OSX_SYSROOT}' is not the pinned SDK for ${CMAKE_OSX_ARCHITECTURES} ('${_mav_pin}').\n"
        "Configure through a shipyard preset (mavericks-cross), or pass "
        "-DCMAKE_TOOLCHAIN_FILE=${MAVERICKS_SHARED_DIR}/MavericksToolchain.cmake. See SKILL.md \"SDK pinning\".")
    endif()
  elseif(_mav_na EQUAL 0)
    # spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- a plain
    # `cmake -S . -B b` on a modern Mac sets no CMAKE_OSX_ARCHITECTURES at all (it comes only from the
    # preset / toolchain file / an explicit -D, never from AppleClang detection). That is the FIRST
    # thing every newly-red consumer hits, so it gets the same actionable guidance as a wrong sysroot,
    # not the "one arch per cross configure" message meant for 2+ arches.
    message(FATAL_ERROR
      "CMAKE_OSX_ARCHITECTURES is empty -- no arch means no pinned SDK to check.\n"
      "Configure through a shipyard preset (mavericks-cross), or pass "
      "-DCMAKE_TOOLCHAIN_FILE=${MAVERICKS_SHARED_DIR}/MavericksToolchain.cmake. See SKILL.md \"SDK pinning\".")
  else()
    message(FATAL_ERROR "include(Mavericks): one arch per cross configure (got '${CMAKE_OSX_ARCHITECTURES}'); build each and merge")
  endif()
endif()

include(RequireAppleClang)      # reject gcc / Homebrew / pkgsrc clang
include(MavericksFetch)         # mavericks_fetch_sdk()
include(MavericksCompatGuard)   # mavericks_assert_binary_compatible()
include(MavericksVersion)       # mavericks_resolve_version() -- VERSION is derived, never committed
include(MavericksDecisions)     # mavericks_require_icon() -- forced icon decision
