# MavericksCompatGuard.cmake -- defines mavericks_assert_binary_compatible(). No side effects
# (no compiler gate, no deploy-target/arch defaults), so a consumer that can't use
# include(Mavericks) (e.g. LANGUAGES NONE / Go) can include just this module.

# Capture the install dir (this file sits alongside scripts/) at include time.
set(MAVERICKS_SHARED_DIR "${CMAKE_CURRENT_LIST_DIR}" CACHE INTERNAL "mavericks-shipyard root")

# mavericks_assert_binary_compatible(<target> [OBJC_STRICT]): after linking <target>, assert its
# Mach-O holds exactly this configure's arches, that every slice records its arch's pinned minos
# and SDK (scripts/sdk-pins.sh; SKILL.md "SDK pinning"), and that it is free of post-10.9 undefined
# imports. With OBJC_STRICT, also that its x86_64 slice sends no Objective-C message the 10.9
# floor cannot answer, as the strict analyzer measures it (scripts/assert_binary_compatible.sh
# header); without it, the guard's selector list checks the Objective-C half, as it always has.
# Forwards these into the guard's env (baked at configure time):
#   MAVERICKS_DEVIATIONS_ROOT         CMAKE_SOURCE_DIR, whose INGREDIENTS.md declares any sdk-pin:<glob>
#                                     exemption (a POST_BUILD command runs in the build tree, where the
#                                     guard's default -- the current directory -- has none)
#   MAVERICKS_ALLOW_ARCHS             CMAKE_OSX_ARCHITECTURES, when set (the guard defaults to x86_64)
#   MAVERICKS_POST_10_9_SYMBOLS       extra post-10.9 symbols that must not be undefined imports
#   MAVERICKS_REQUIRE_DEFINED_SYMBOLS symbols that MUST be present as defined (e.g. shims)
# and, with OBJC_STRICT only:
#   MAVERGREEN_OBJC_STRICT             1
#   MAVERGREEN_OBJC_REFERENCES         the reference set; default this shipyard's reference/objc
#   MAVERGREEN_OBJC_ROOT               the shipped root (default: the target's own directory)
#   MAVERGREEN_OBJC_BUILD_EVIDENCE     each when set: the analyzer's build evidence, Objective-C
#   MAVERGREEN_OBJC_PROVIDER_PREFIX    provider prefix and provider source receipt
#   MAVERGREEN_OBJC_SOURCE_RECEIPT
# With OBJC_STRICT, MAVERICKS_POST_10_9_SELECTORS and MAVERICKS_ALLOW_SELECTORS, raw selector
# lists the analyzer replaces, stop the configure with what replaces them. Without it, an analyzer
# knob set in CMake stops the configure, rather than be silently ignored.
function(mavericks_assert_binary_compatible tgt)
  cmake_parse_arguments(_mabc "OBJC_STRICT" "" "" ${ARGN})
  if(_mabc_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "mavericks_assert_binary_compatible(${tgt}): unknown argument(s) ${_mabc_UNPARSED_ARGUMENTS}")
  endif()
  set(_objc_knobs MAVERGREEN_OBJC_REFERENCES MAVERGREEN_OBJC_ROOT MAVERGREEN_OBJC_BUILD_EVIDENCE
    MAVERGREEN_OBJC_PROVIDER_PREFIX MAVERGREEN_OBJC_SOURCE_RECEIPT)
  if(_mabc_OBJC_STRICT)
    # spec: scripts/assert_binary_compatible.sh header -- retired knobs fail, never silently ignored.
    foreach(_retired MAVERICKS_POST_10_9_SELECTORS MAVERICKS_ALLOW_SELECTORS)
      if(NOT "${${_retired}}" STREQUAL "" OR NOT "$ENV{${_retired}}" STREQUAL "")
        message(FATAL_ERROR "${_retired} is retired under OBJC_STRICT: the compat guard's strict Objective-C "
          "analyzer measures every send against the versioned reference set (reference/objc), and a selector "
          "string proves nothing about a send. Remove it. A send the analyzer blocks that your code guards needs "
          "a reviewed, scoped INGREDIENTS.md \"- objc-api:<artifact path>: evidence=<file>#<record id> <review "
          "reason>\" deviation (scripts/assert_binary_compatible.sh header).")
      endif()
    endforeach()
  else()
    foreach(_objc ${_objc_knobs})
      if(${_objc})
        message(FATAL_ERROR "${_objc} is the strict Objective-C analyzer's, which mavericks_assert_binary_compatible(${tgt}) "
          "needs OBJC_STRICT to run: add OBJC_STRICT, or remove ${_objc}.")
      endif()
    endforeach()
  endif()
  set(_cmd sh "${MAVERICKS_SHARED_DIR}/scripts/assert_binary_compatible.sh" "$<TARGET_FILE:${tgt}>")
  set(_env "MAVERICKS_DEVIATIONS_ROOT=${CMAKE_SOURCE_DIR}")
  # The exact arch set this configure builds: an arm64-only updater slice is not an x86_64 binary.
  if(CMAKE_OSX_ARCHITECTURES)
    string(REPLACE ";" " " _archs "${CMAKE_OSX_ARCHITECTURES}")
    list(APPEND _env "MAVERICKS_ALLOW_ARCHS=${_archs}")
  endif()
  if(MAVERICKS_POST_10_9_SYMBOLS)
    list(APPEND _env "MAVERICKS_POST_10_9_SYMBOLS=${MAVERICKS_POST_10_9_SYMBOLS}")
  endif()
  if(MAVERICKS_REQUIRE_DEFINED_SYMBOLS)
    list(APPEND _env "MAVERICKS_REQUIRE_DEFINED_SYMBOLS=${MAVERICKS_REQUIRE_DEFINED_SYMBOLS}")
  endif()
  if(_mabc_OBJC_STRICT)
    list(APPEND _env "MAVERGREEN_OBJC_STRICT=1")
    # The reference set is staged with the scripts (CMakeLists.txt installs reference/objc beside them);
    # naming it here keeps a consumer's guard on the shipyard it configured with.
    if(MAVERGREEN_OBJC_REFERENCES)
      list(APPEND _env "MAVERGREEN_OBJC_REFERENCES=${MAVERGREEN_OBJC_REFERENCES}")
    else()
      list(APPEND _env "MAVERGREEN_OBJC_REFERENCES=${MAVERICKS_SHARED_DIR}/reference/objc")
    endif()
    foreach(_objc MAVERGREEN_OBJC_ROOT MAVERGREEN_OBJC_BUILD_EVIDENCE MAVERGREEN_OBJC_PROVIDER_PREFIX MAVERGREEN_OBJC_SOURCE_RECEIPT)
      if(${_objc})
        list(APPEND _env "${_objc}=${${_objc}}")
      endif()
    endforeach()
  endif()
  set(_cmd ${CMAKE_COMMAND} -E env ${_env} ${_cmd})
  add_custom_command(TARGET ${tgt} POST_BUILD
    COMMAND ${_cmd}
    VERBATIM COMMENT "compat guard: assert ${tgt} is 10.9-safe")
endfunction()
