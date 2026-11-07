# usage: cmake -DMODULE_DIR=<dir> -DCOMPILER=<path> -DROOT=<dir> -DRESULT=<file> -P tools.cmake
#        builds the pinned host tools and writes their bin directory
cmake_minimum_required(VERSION 3.19)
list(APPEND CMAKE_MODULE_PATH "${MODULE_DIR}")
include(MavericksHostTools)
mavericks_build_host_tools(dir OUTPUT_ROOT "${ROOT}" COMPILER "${COMPILER}")
file(WRITE "${RESULT}" "${dir}")
