#   usage: include(MavericksMode)
#          Sets MAVERICKS_MODE to "mavericks" on an OS X 10.9.x host and "modern" on every other host,
#          and stops the configure when MAVERICKS_EXPECTED_MODE is defined.
#          mavericks_build_mode(<out_var>) sets <out_var> the same way, for a consumer that layers
#          modes of its own on top. scripts/mavericks_mode.sh is the sh companion.

if(NOT APPLE)
  message(FATAL_ERROR "mavericks-* builds target macOS.")
endif()

function(mavericks_build_mode out_var)
  execute_process(COMMAND sw_vers -productVersion
    OUTPUT_VARIABLE _osv OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
  if(_osv MATCHES "^10\\.9\\.")
    set(${out_var} "mavericks" PARENT_SCOPE)
  else()
    set(${out_var} "modern" PARENT_SCOPE)
  endif()
endfunction()

if(DEFINED MAVERICKS_EXPECTED_MODE)
  message(FATAL_ERROR "MAVERICKS_EXPECTED_MODE is gone: every shipyard preset configures on every host. Drop it from your preset and inherit mavericks-x86_64 or macos-arm64.")
endif()

mavericks_build_mode(MAVERICKS_MODE)
message(STATUS "mavericks build mode: ${MAVERICKS_MODE}")
