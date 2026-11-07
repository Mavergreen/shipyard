# usage: cmake -DMODULE_DIR=<dir> -DCOMPILER=<path> -DPROJECT=<xcodeproj> -DTARGETS=<a;b> -DPREFIXES=<A;B>
#              -DOUT=<dir> -DRESULT=<file> -P export.cmake
#        exports the targets' sources and writes the validated generated CMake file's path
cmake_minimum_required(VERSION 3.19)
list(APPEND CMAKE_MODULE_PATH "${MODULE_DIR}")
include(MavericksXcodeInputs)
if(DROP)
  set(_MXI_TEST_EXPORTER_WRAPPER "${CMAKE_CURRENT_LIST_DIR}/drop-line" "${DROP}")
endif()
mavericks_export_xcode_sources(file PROJECT "${PROJECT}" TARGETS ${TARGETS} PREFIXES ${PREFIXES}
  HOST_COMPILER "${COMPILER}" OUTPUT_DIR "${OUT}")
file(WRITE "${RESULT}" "${file}")
