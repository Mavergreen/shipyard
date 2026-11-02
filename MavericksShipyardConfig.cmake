# MavericksShipyardConfig.cmake -- found by find_package(MavericksShipyard).
#
# Installed alongside the modules + scripts under <prefix>/share/cmake/
# MavericksShipyard/. Adds that directory to CMAKE_MODULE_PATH so consumers
# can `include(Mavericks)` (which then finds MavericksMode/RequireAppleClang and
# resolves scripts/ from its own location). This is a find_package package meant
# to be INSTALLED to a prefix -- installed by the shipyard pkg and found by
# shipyard-cmake -- NOT vendored/submoduled into a consumer's source tree (the
# guard below enforces this so consumers don't silently drift onto a stale
# in-tree copy).

# spec: 2026-10-09 C5 -- on a macOS host only a cmake product paired with a shipyard, <X>/cmake/bin/cmake
#       beside <X>/shipyard/bin/shipyard-cmake, at or above the minimum, may configure against it. Any
#       shipyard may be the one loaded, so a CMAKE_PREFIX_PATH dev prefix needs no cmake beside it. A
#       guardrail, not a sandbox: CMAKE_COMMAND is an ordinary variable.
# spec: R-P1-23 -- CMAKE_HOST_APPLE, not APPLE: the running cmake is a property of the host, and a
#       Linux host has no cmake product to demand, so it skips the check.
# spec: tests/shipyard-cmake-refusal-test.sh -- the install configures the minimum in; a CHECKOUT,
#       where it is still a placeholder, takes the Kitware part of its own pin.
if(CMAKE_HOST_APPLE)
  set(_shipyard_cmake_min "@SHIPYARD_CMAKE_MIN@")
  if(NOT _shipyard_cmake_min MATCHES "^[0-9]")
    file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/.mavergreen/ingredients/cmake/VERSION" _shipyard_cmake_min LIMIT_COUNT 1)
    string(REGEX REPLACE "-mavericks\\..*$" "" _shipyard_cmake_min "${_shipyard_cmake_min}")
  endif()
  get_filename_component(_shipyard_cmake_used "${CMAKE_COMMAND}" REALPATH)
  string(REGEX REPLACE "/cmake/bin/cmake$" "" _shipyard_cmake_pair "${_shipyard_cmake_used}")
  if(_shipyard_cmake_pair STREQUAL _shipyard_cmake_used
     OR NOT EXISTS "${_shipyard_cmake_pair}/shipyard/bin/shipyard-cmake"
     OR CMAKE_VERSION VERSION_LESS _shipyard_cmake_min)
    message(FATAL_ERROR
      "mavericks-shipyard must be configured with shipyard-cmake (/usr/local/mavergreen/bin/shipyard-cmake), "
      "which runs the Mavergreen cmake product installed beside shipyard, CMake ${_shipyard_cmake_min} or later. "
      "In GitHub Actions, Mavergreen/shipyard/.github/actions/install@v1 provides both. This configure is "
      "running ${CMAKE_COMMAND}, CMake ${CMAKE_VERSION}. IDEs with a configurable CMake executable: point that setting at "
      "/usr/local/mavergreen/bin/shipyard-cmake.")
  endif()
endif()

# Fail clearly if consumed VENDORED: if this config resolves from INSIDE the
# consumer's source tree, it's a submodule/copied-in checkout. Install it instead
# (README "Install (once)"). Deliberate vendoring: -DMAVERICKS_ALLOW_VENDORED=ON.
if(NOT MAVERICKS_ALLOW_VENDORED)
  file(RELATIVE_PATH _mav_rel "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_LIST_DIR}")
  if(NOT _mav_rel MATCHES "^\\.\\.")   # not "../..." => under the consumer tree
    message(FATAL_ERROR
      "mavericks-shipyard appears VENDORED: its config is inside the consumer "
      "tree (${CMAKE_CURRENT_LIST_DIR} under ${CMAKE_SOURCE_DIR}). It is a "
      "find_package package -- installed by the shipyard pkg and found by "
      "shipyard-cmake; do not vendor or submodule it. See the README \"Install (once)\" "
      "section. Override deliberately with -DMAVERICKS_ALLOW_VENDORED=ON.")
  endif()
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")

# Version resolution is included HERE, not left to include(Mavericks), because every product needs it
# and not every product includes that umbrella: container-tools' root is project(LANGUAGES NONE) and
# deliberately skips the AppleClang gate, so find_package alone left mavericks_resolve_version()
# undefined and the configure failed. Defining a function is language-agnostic and costs nothing.
include(MavericksVersion)

# Convenience: expose the presets file's installed path (CMakePresets.json can
# $env-include it; it cannot see find_package results directly).
set(MavericksShipyard_PRESETS "${CMAKE_CURRENT_LIST_DIR}/mavericks-presets.json")

# Installed scripts dir, so consumers reference ${MavericksShipyard_SCRIPTS}/assert_binary_compatible.sh
# instead of hard-coding "${MavericksShipyard_DIR}/scripts/...".
set(MavericksShipyard_SCRIPTS "${CMAKE_CURRENT_LIST_DIR}/scripts")

# Scaffold a sensible default Renovate config for consumer projects. On configure,
# if the top-level project is a git repo that has NO .github/renovate.json, write
# one that extends this repo's shared preset -- which turns on config:recommended +
# automerge AND (via the preset's customManager) lets Renovate act on new upstream
# mavericks-shipyard commits. Never overwrites an existing config (if they
# already have one, leave it alone). Opt out with -DMAVERICKS_NO_RENOVATE_SCAFFOLD=ON.
if(NOT MAVERICKS_NO_RENOVATE_SCAFFOLD AND EXISTS "${CMAKE_SOURCE_DIR}/.git")
  set(_mav_renovate "${CMAKE_SOURCE_DIR}/.github/renovate.json")
  if(NOT EXISTS "${_mav_renovate}")
    file(MAKE_DIRECTORY "${CMAKE_SOURCE_DIR}/.github")
    file(WRITE "${_mav_renovate}"
"{
  \"$schema\": \"https://docs.renovatebot.com/renovate-schema.json\",
  \"extends\": [\"github>Mavergreen/shipyard\"]
}
")
    message(STATUS "mavericks-shipyard: created a default ${_mav_renovate} "
                   "(extends the shared Renovate preset; opt out with -DMAVERICKS_NO_RENOVATE_SCAFFOLD=ON)")
  endif()
endif()
