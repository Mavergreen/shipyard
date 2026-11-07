# MavergreenMode.cmake -- native/cross detection + preset guard, as reusable functions.
#
# "native" = building ON OS X 10.9 (Darwin 13). "cross" = a modern host building for
# 10.9. Consumers with EXTRA modes (e.g. mavericks-docker's "iso") call mavergreen_build_mode()
# for the base decision and layer their own on top, instead of forking the detector.
#
# For the common case, including this module (via include(Mavergreen)) still sets
# MAVERGREEN_MODE and guards against MAVERGREEN_EXPECTED_MODE -- unchanged behavior.

if(NOT APPLE)
  message(FATAL_ERROR "mavericks-* builds target macOS.")
endif()

# mavergreen_build_mode(<out_var>): set out_var to "native" (host is 10.9.x) or "cross".
function(mavergreen_build_mode out_var)
  execute_process(COMMAND sw_vers -productVersion
    OUTPUT_VARIABLE _osv OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
  if(_osv MATCHES "^10\\.9\\.")
    set(${out_var} "native" PARENT_SCOPE)
  else()
    set(${out_var} "cross" PARENT_SCOPE)
  endif()
endfunction()

# mavergreen_require_expected_mode(<mode>): if MAVERGREEN_EXPECTED_MODE is set (by the
# preset) and differs from <mode>, fail fast -- wrong preset for this host.
function(mavergreen_require_expected_mode mode)
  if(DEFINED MAVERGREEN_EXPECTED_MODE AND NOT MAVERGREEN_EXPECTED_MODE STREQUAL mode)
    message(FATAL_ERROR
      "This preset expects a '${MAVERGREEN_EXPECTED_MODE}' build but this host does a "
      "'${mode}' build -- wrong preset for this machine.")
  endif()
endfunction()

# Back-compat for include(Mavergreen): set MAVERGREEN_MODE + guard, as before.
mavergreen_build_mode(MAVERGREEN_MODE)
message(STATUS "mavergreen build mode: ${MAVERGREEN_MODE}")
mavergreen_require_expected_mode("${MAVERGREEN_MODE}")
