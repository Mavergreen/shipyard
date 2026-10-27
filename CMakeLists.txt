cmake_minimum_required(VERSION 3.16)
# VERSION (a gitignored build product) wins when present -- release.yml writes it. Otherwise derive
# from the commit count, so a developer's `cmake --install` from a checkout stamps the REAL version
# rather than the bare line: an install is a snapshot with no staleness signal of its own, and the
# number it carries is the only way to tell one apart from another. UPSTREAM_VERSION is the last
# resort, for a tarball with no .git (it yields the line, which is honest about being imprecise).
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION")
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" _MSC_VERSION LIMIT_COUNT 1)
else()
  execute_process(
    COMMAND sh "${CMAKE_CURRENT_SOURCE_DIR}/scripts/shipyard-version.sh"
    OUTPUT_VARIABLE _MSC_VERSION_OUT ERROR_QUIET RESULT_VARIABLE _MSC_VERSION_RC
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(_MSC_VERSION_RC EQUAL 0)
    string(REGEX MATCH "FULL=([^\n]*)" _MSC_VERSION_MATCH "${_MSC_VERSION_OUT}")
    set(_MSC_VERSION "${CMAKE_MATCH_1}")
  else()
    file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/UPSTREAM_VERSION" _MSC_VERSION LIMIT_COUNT 1)
  endif()
endif()
project(MavericksShipyard VERSION ${_MSC_VERSION} LANGUAGES NONE)

# The Sparkle updater that keeps an installed shipyard current. OPT-IN: shipyard is LANGUAGES NONE
# and compiles nothing, so `cmake --install` works on a box with no ObjC compiler -- and the payload
# stays buildable where there is no Objective-C at all. Only the pkg job turns this on.
#
# Built once per arch (x86_64/10.9 and arm64/11.0) rather than a single fat build:
# CMAKE_OSX_ARCHITECTURES and the deployment target are directory-scoped, and a fat
# CMAKE_OSX_ARCHITECTURES can't carry two floors -- arm64 has no 10.9. The two single-arch builds
# share the same PRODUCT, so the same name and bundle id, and are merged into ONE universal .app by
# scripts/lipo-merge-tree.sh in the release, not picked between.
option(SHIPYARD_BUILD_UPDATER "Build the Sparkle updater app (needed only to package the pkg)" OFF)
if(SHIPYARD_BUILD_UPDATER)
  enable_language(OBJC)
  # Every slice embeds Sparkle's FAT framework, so the two single-arch builds carry an identical
  # framework and lipo-merge-tree.sh only has to merge the updater's own executable.
  include("${CMAKE_CURRENT_SOURCE_DIR}/MavericksSparkle.cmake")

  # ONE universal app (spec 2026-09-11): built once per arch -- x86_64/10.9 and arm64/11.0, since a
  # deployment floor is per-configure and arm64 has no 10.9 -- and merged by lipo-merge-tree.sh in the
  # release. One PRODUCT for both builds, so the merge is of one app, not two.
  mavericks_add_updater_app(
    PRODUCT shipyard
    PRODUCT_NAME "Mavericks Shipyard"
    VERSION "${PROJECT_VERSION}"
    LOG_PREFIX "MavShipyardUpdater"
    CONFIRM_TITLE "Mavericks Shipyard updated"
    CONFIRM_BODY "Mavericks Shipyard in /usr/local/mavergreen/shipyard was updated."
    RELAUNCH_MARKER "/tmp/.mavericks-shipyard-updater-relaunched"
    ALLOW_GENERIC
    # no PANE_HINT_KEY -> a background-found update posts an NSUserNotification. shipyard has no UI.
  )
endif()

# This project ships CMake modules + helper scripts (no compiled artifacts). It
# installs itself as a find_package() config package so consumers can just:
#   find_package(MavericksShipyard REQUIRED)
#   include(Mavericks)
# instead of vendoring a submodule.
# spec: 2026-10-09 C4 -- consumers find this package through bin/shipyard-cmake, which runs the cmake
#       product in the sibling prefix with this prefix on CMAKE_PREFIX_PATH. To develop shipyard,
#       install it into a prefix of your own and configure with CMAKE_PREFIX_PATH=<that prefix>
#       shipyard-cmake; the launcher appends, so the dev copy is found first.

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

set(_dest "${CMAKE_INSTALL_DATADIR}/cmake/MavericksShipyard")

# spec: 2026-10-09 C5 -- the config refuses a cmake below the Kitware part of shipyard's cmake pin.
#       -DSHIPYARD_CMAKE_MIN sets another for one configure, so a fixture can pair shipyard with the
#       host's cmake; it is dropped from the cache so that a later configure reads the pin again.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS components/cmake/version)
if(DEFINED CACHE{SHIPYARD_CMAKE_MIN})
  set(_shipyard_cmake_min "$CACHE{SHIPYARD_CMAKE_MIN}")
  unset(SHIPYARD_CMAKE_MIN CACHE)
else()
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/components/cmake/version" _shipyard_cmake_min LIMIT_COUNT 1)
  string(REGEX REPLACE "-mavericks\\.[0-9]+$" "" _shipyard_cmake_min "${_shipyard_cmake_min}")
endif()
# spec: MavericksShipyardConfig.cmake -- a minimum that is not a version reads as a checkout's
#       placeholder there, and every consumer would then fail on a missing components/cmake/version.
if(NOT _shipyard_cmake_min MATCHES "^[0-9]+(\\.[0-9]+)*$")
  message(FATAL_ERROR "shipyard's cmake minimum is '${_shipyard_cmake_min}', not a version: "
    "components/cmake/version must hold X.Y.Z-mavericks.N, and -DSHIPYARD_CMAKE_MIN must be X.Y.Z")
endif()
set(SHIPYARD_CMAKE_MIN "${_shipyard_cmake_min}")
configure_file(MavericksShipyardConfig.cmake "${CMAKE_CURRENT_BINARY_DIR}/MavericksShipyardConfig.cmake" @ONLY)

# spec: 2026-10-09 C4 -- the launchers, plus bin/{cmake,ctest,cpack} linked to them so a build
#       directory configured before the cmake product existed still regenerates; the pkg keeps those
#       three out of the link farm. Revisit at the flag day: the move to /opt breaks those build
#       directories anyway.
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/compat")
foreach(_tool cmake ctest cpack)
  install(PROGRAMS scripts/shipyard-launcher.sh DESTINATION bin RENAME "shipyard-${_tool}")
  file(CREATE_LINK "shipyard-${_tool}" "${CMAKE_CURRENT_BINARY_DIR}/compat/${_tool}" SYMBOLIC)
  install(PROGRAMS "${CMAKE_CURRENT_BINARY_DIR}/compat/${_tool}" DESTINATION bin)
endforeach()

install(FILES
  "${CMAKE_CURRENT_BINARY_DIR}/MavericksShipyardConfig.cmake"
  Mavericks.cmake
  MavericksMode.cmake
  RequireAppleClang.cmake
  MavericksFetch.cmake
  MavericksToolchain.cmake
  MavericksCompatGuard.cmake
  MavericksSparkle.cmake
  MavericksVersion.cmake
  MavericksDecisions.cmake
  default.json
  DESTINATION "${_dest}")

# platform: CMake expands a preset's ${fileDir} against the file of the preset being CONFIGURED, not
#           the file that wrote the macro, so a consumer inheriting mavericks-cross from the installed
#           presets got "Could not find toolchain file: <consumer dir>/MavericksToolchain.cmake"
#           (CMake 3.28, 4.4.3). The installed copy names the installed toolchain file absolutely.
#           The source keeps ${fileDir}: it is the token replaced here, it keeps the source valid
#           JSON, and it is still right for the one caller it can serve -- a CMakePresets.json
#           beside it, whose ${fileDir} is this directory too. Nothing consumes the source that way.
# spec: tests/installed-presets-test.sh -- baked at INSTALL time, not configure time, so the path is
#       the prefix `cmake --install --prefix` names; file(INSTALL) adds $ENV{DESTDIR} to where the
#       file lands, never to the path written inside it, so a pkg stage bakes the real prefix.
set(_msc_presets_code [[
  if(IS_ABSOLUTE "@_dest@")
    set(_msc_to "@_dest@")
  else()
    set(_msc_to "${CMAKE_INSTALL_PREFIX}/@_dest@")
  endif()
  file(READ "@CMAKE_CURRENT_SOURCE_DIR@/mavericks-presets.json" _msc_json)
  set(_msc_token "\${fileDir}/MavericksToolchain.cmake")
  string(FIND "${_msc_json}" "${_msc_token}" _msc_at)
  if(_msc_at EQUAL -1)
    message(FATAL_ERROR "mavericks-presets.json has no ${_msc_token} to replace with the installed toolchain file")
  endif()
  string(REPLACE "${_msc_token}" "${_msc_to}/MavericksToolchain.cmake" _msc_json "${_msc_json}")
  if(_msc_json MATCHES "fileDir")
    message(FATAL_ERROR "mavericks-presets.json still names \${fileDir} after install-time substitution")
  endif()
  file(WRITE "@CMAKE_CURRENT_BINARY_DIR@/installed-presets/mavericks-presets.json" "${_msc_json}")
  file(INSTALL DESTINATION "${_msc_to}" TYPE FILE
    FILES "@CMAKE_CURRENT_BINARY_DIR@/installed-presets/mavericks-presets.json")
]])
string(CONFIGURE "${_msc_presets_code}" _msc_presets_code @ONLY)
install(CODE "${_msc_presets_code}")

# Scripts keep their executable bit (they are run via `sh` but stay +x for direct use).
# scripts/ carries the Sparkle fetch scripts + native signer/keygen sources too.
install(DIRECTORY scripts DESTINATION "${_dest}" USE_SOURCE_PERMISSIONS)
# Sparkle updater templates (configure_file'd per product by MavericksSparkle.cmake).
install(DIRECTORY updater DESTINATION "${_dest}")

write_basic_package_version_file(
  "${CMAKE_CURRENT_BINARY_DIR}/MavericksShipyardConfigVersion.cmake"
  VERSION "${PROJECT_VERSION}"
  COMPATIBILITY SameMajorVersion)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/MavericksShipyardConfigVersion.cmake"
  DESTINATION "${_dest}")

# Self-tests for the shared shell helpers.
# `shipyard-cmake -S . -B build && shipyard-ctest --test-dir build`.
enable_testing()
find_program(BATS_EXECUTABLE bats)
if(BATS_EXECUTABLE)
  add_test(NAME mavericks-fetch
    COMMAND ${BATS_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/mavericks_fetch.bats)
  add_test(NAME clone-pinned
    COMMAND ${BATS_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/clone_pinned.bats)
  add_test(NAME compat-guard
    COMMAND ${BATS_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/compat_guard.bats)
  add_test(NAME gen-appcast
    COMMAND ${BATS_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/gen_appcast.bats)
  add_test(NAME relaunch-decision
    COMMAND ${BATS_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/relaunch_decision.bats)
else()
  message(STATUS "bats not found -- shell helper tests won't run via ctest (install bats to enable)")
endif()

# Prove the à-la-carte modules load without include(Mavericks) / the AppleClang gate.
# Point find_package at THIS source tree (it carries the config + modules).
add_test(NAME standalone-include
  COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/standalone-include.sh ${CMAKE_CURRENT_SOURCE_DIR})

# Prove include(Mavericks) is universally includable: auto-scoped gate (no
# MAVERICKS_REQUIRE_LANGS), LANGUAGES NONE no-op, and multi-arch safe.
add_test(NAME umbrella-langs
  COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/umbrella-langs.sh ${CMAKE_CURRENT_SOURCE_DIR})

# Both configure a scratch consumer through shipyard-cmake (MavericksShipyardConfig.cmake
# refuses any other cmake) and exit 77 to SKIP when none is reachable -- a box that hasn't
# installed the shipyard pkg. Without this, ctest counts a 77 exit as Failed, not Skipped.
set_tests_properties(standalone-include umbrella-langs PROPERTIES SKIP_RETURN_CODE 77)

# Prove stage_updater.sh stages an updater .app + LaunchAgent and renders the templates.
add_test(NAME stage-updater
  COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/stage_updater.sh ${CMAKE_CURRENT_SOURCE_DIR})

# Prove sign_and_appcast.sh signs a pkg and emits an appcast with the EdDSA enclosure attrs.
add_test(NAME sign-and-appcast
  COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/sign_and_appcast.sh ${CMAKE_CURRENT_SOURCE_DIR})

# Prove the Renovate preset is valid and carries the shared Recaulk manager.
add_test(NAME renovate-preset
  COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/renovate_preset.sh)
