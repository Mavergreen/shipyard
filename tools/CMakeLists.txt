# usage: configured only by MavericksHostTools.cmake, as a separate host-native configure:
#        -DMULLE_SOURCE=<verified exporter source>
cmake_minimum_required(VERSION 3.19)
project(mavericks_host_tools LANGUAGES C OBJC)
if(NOT IS_DIRECTORY "${MULLE_SOURCE}")
  message(FATAL_ERROR "MULLE_SOURCE '${MULLE_SOURCE}' is not a directory")
endif()
add_subdirectory("${MULLE_SOURCE}" mulle)

add_executable(mavericks-xcode-inputs xcode-project-inputs.m)
target_compile_options(mavericks-xcode-inputs PRIVATE -fobjc-arc -Wall -Werror)
target_link_libraries(mavericks-xcode-inputs PRIVATE "-framework Foundation")
