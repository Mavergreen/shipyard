# MavericksMode.cmake -- native/cross detection + preset guard, as reusable functions.
#
# "native" = building ON OS X 10.9 (Darwin 13). "cross" = a modern host building for
# 10.9. Consumers with EXTRA modes (e.g. mavericks-docker's "iso") call mavericks_build_mode()
# for the base decision and layer their own on top, instead of forking the detector.
#
# For the common case, including this module (via include(Mavericks)) still sets
# MAVERICKS_MODE and guards against MAVERICKS_EXPECTED_MODE -- unchanged behavior.

if(NOT APPLE)
  message(FATAL_ERROR "mavericks-* builds target macOS.")
endif()

# mavericks_build_mode(<out_var>): set out_var to "native" (host is 10.9.x) or "cross".
function(mavericks_build_mode out_var)
  execute_process(COMMAND sw_vers -productVersion
    OUTPUT_VARIABLE _osv OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
  if(_osv MATCHES "^10\\.9\\.")
    set(${out_var} "native" PARENT_SCOPE)
  else()
    set(${out_var} "cross" PARENT_SCOPE)
  endif()
endfunction()

# mavericks_require_expected_mode(<mode>): if MAVERICKS_EXPECTED_MODE is set (by the
# preset) and differs from <mode>, fail fast -- wrong preset for this host. "modern" (the
# macos-arm64 preset) expects any host that is not 10.9, which mavericks_build_mode calls "cross".
function(mavericks_require_expected_mode mode)
  if(DEFINED MAVERICKS_EXPECTED_MODE AND NOT MAVERICKS_EXPECTED_MODE STREQUAL mode
     AND NOT (MAVERICKS_EXPECTED_MODE STREQUAL "modern" AND mode STREQUAL "cross"))
    message(FATAL_ERROR
      "This preset expects a '${MAVERICKS_EXPECTED_MODE}' build but this host does a "
      "'${mode}' build -- wrong preset for this machine.")
  endif()
endfunction()

# Back-compat for include(Mavericks): set MAVERICKS_MODE + guard, as before.
mavericks_build_mode(MAVERICKS_MODE)
message(STATUS "mavericks build mode: ${MAVERICKS_MODE}")
mavericks_require_expected_mode("${MAVERICKS_MODE}")
