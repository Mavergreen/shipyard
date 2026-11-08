# usage: configured only by MavergreenHostTools.cmake, as a separate host-native configure:
#        -DMULLE_SOURCE=<verified exporter source>
cmake_minimum_required(VERSION 3.19)
project(mavergreen_host_tools LANGUAGES C OBJC)
if(NOT IS_DIRECTORY "${MULLE_SOURCE}")
  message(FATAL_ERROR "MULLE_SOURCE '${MULLE_SOURCE}' is not a directory")
endif()
add_subdirectory("${MULLE_SOURCE}" mulle)

add_executable(mavergreen-xcode-inputs xcode-project-inputs.m)
target_compile_options(mavergreen-xcode-inputs PRIVATE -fobjc-arc -Wall -Werror)
target_link_libraries(mavergreen-xcode-inputs PRIVATE "-framework Foundation")

add_executable(mavergreen-resource-extract resource-extract.m)
target_compile_options(mavergreen-resource-extract PRIVATE -fobjc-arc -Wall -Werror)
target_link_libraries(mavergreen-resource-extract PRIVATE "-framework Foundation" archive)
