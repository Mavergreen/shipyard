# MavericksCompatGuard.cmake -- defines mavericks_assert_binary_compatible(). No side effects
# (no compiler gate, no deploy-target/arch defaults), so a consumer that can't use
# include(Mavericks) (e.g. LANGUAGES NONE / Go) can include just this module.

# Capture the install dir (this file sits alongside scripts/) at include time.
set(MAVERICKS_SHARED_DIR "${CMAKE_CURRENT_LIST_DIR}" CACHE INTERNAL "mavericks-shipyard root")

# mavericks_assert_binary_compatible(<target>): after linking <target>, assert its Mach-O holds
# exactly this configure's arches, that every slice records its arch's pinned minos and SDK
# (scripts/sdk-pins.sh; SKILL.md "SDK pinning"), and that it is free of post-10.9 undefined
# imports. Forwards these into the guard's env (baked at configure time):
#   MAVERICKS_ALLOW_ARCHS             CMAKE_OSX_ARCHITECTURES, when set (the guard defaults to x86_64)
#   MAVERICKS_POST_10_9_SYMBOLS       extra post-10.9 symbols that must not be undefined imports
#   MAVERICKS_REQUIRE_DEFINED_SYMBOLS symbols that MUST be present as defined (e.g. shims)
function(mavericks_assert_binary_compatible tgt)
  set(_cmd sh "${MAVERICKS_SHARED_DIR}/scripts/assert_binary_compatible.sh" "$<TARGET_FILE:${tgt}>")
  set(_env)
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
  if(_env)
    set(_cmd ${CMAKE_COMMAND} -E env ${_env} ${_cmd})
  endif()
  add_custom_command(TARGET ${tgt} POST_BUILD
    COMMAND ${_cmd}
    VERBATIM COMMENT "compat guard: assert ${tgt} is 10.9-safe")
endfunction()
