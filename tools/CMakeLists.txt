# usage: configured only by MavericksHostTools.cmake, as a separate host-native configure:
#        -DMULLE_SOURCE=<verified exporter source>
cmake_minimum_required(VERSION 3.19)
project(mavericks_host_tools LANGUAGES C)
if(NOT IS_DIRECTORY "${MULLE_SOURCE}")
  message(FATAL_ERROR "MULLE_SOURCE '${MULLE_SOURCE}' is not a directory")
endif()
add_subdirectory("${MULLE_SOURCE}" mulle)
