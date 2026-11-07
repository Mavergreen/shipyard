# usage: cmake -DMODULE_DIR=<dir> -DCOMPILER=<path> -DSOURCE=<dir> -DROOT=<dir> -DRESULT=<file> -P build.cmake
#        builds the host tools from SOURCE (a test-supplied exporter source) and writes their directory
cmake_minimum_required(VERSION 3.19)
list(APPEND CMAKE_MODULE_PATH "${MODULE_DIR}")
include(MavericksHostTools)
mavericks_build_host_tools(dir OUTPUT_ROOT "${ROOT}" COMPILER "${COMPILER}" MULLE_SOURCE "${SOURCE}")
file(WRITE "${RESULT}" "${dir}")
