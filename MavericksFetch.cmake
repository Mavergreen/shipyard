# MavericksFetch.cmake -- defines mavericks_fetch_sdk(). No side effects, so a
# consumer can include just this module without the compiler gate / mode check.
set(MAVERICKS_SHARED_DIR "${CMAKE_CURRENT_LIST_DIR}" CACHE INTERNAL "mavericks-shipyard root")

# mavericks_fetch_sdk(<out_var> [ARCH x86_64|arm64]): fetch+cache+verify the pinned SDK for ARCH (default
# x86_64: MacOSX10.9.sdk; arm64: MacOSX11.3.sdk) and return its path. The pins live in scripts/sdk-pins.sh.
function(mavericks_fetch_sdk out_var)
  cmake_parse_arguments(A "" "ARCH" "" ${ARGN})
  if(NOT A_ARCH)
    set(A_ARCH x86_64)
  endif()
  execute_process(
    COMMAND sh "${MAVERICKS_SHARED_DIR}/scripts/fetch_sdk.sh" --arch "${A_ARCH}"
    OUTPUT_VARIABLE _sdk OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE _rc)
  if(NOT _rc EQUAL 0)
    message(FATAL_ERROR "fetch_sdk.sh --arch ${A_ARCH} failed")
  endif()
  set(${out_var} "${_sdk}" PARENT_SCOPE)
endfunction()
