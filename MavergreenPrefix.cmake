# MavergreenPrefix.cmake -- defines mavergreen_prefix(<out-var> [<short>]). No side effects at include.
#
#   Sets <out-var> to /opt/mavergreen, or /opt/mavergreen/<short>, by running mavergreen_prefix from
#   scripts/mavergreen-meta.sh. A <short> that lib/name-rules.sh refuses is a FATAL_ERROR.
include_guard(GLOBAL)
set(_MPX_SCRIPTS "${CMAKE_CURRENT_LIST_DIR}/scripts")

function(mavergreen_prefix out_var)
  if(ARGC GREATER 2)
    message(FATAL_ERROR "mavergreen_prefix: usage: mavergreen_prefix(<out-var> [<short>])")
  endif()
  execute_process(
    COMMAND sh -c ". \"$1/mavergreen-meta.sh\" && . \"$1/lib/name-rules.sh\" && shift && mavergreen_prefix \"$@\""
      sh "${_MPX_SCRIPTS}" ${ARGN}
    OUTPUT_VARIABLE _mpx_out
    ERROR_VARIABLE _mpx_err
    RESULT_VARIABLE _mpx_rc
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE)
  if(NOT _mpx_rc EQUAL 0)
    message(FATAL_ERROR "mavergreen_prefix(${ARGN}) exited ${_mpx_rc}: ${_mpx_err}")
  endif()
  set(${out_var} "${_mpx_out}" PARENT_SCOPE)
endfunction()
